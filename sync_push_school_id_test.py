"""
E2E Test: sync-push school_id derivation fix - v7

Strategy:
  1. Pre-cleanup any leftover test data
  2. Login as admin -> get real JWT
  3. Create a test subject (with curriculum="nerdc" for CHECK constraint)
  4. Push lesson with WRONG school_server_id + valid subject_id via sync-push
  5. Query back lesson via REST with service_role key
  6. Verify school_id = JWT school_id, NOT the wrong UUID
  7. Cleanup: delete test lesson + test subject via service_role
"""
import json
import subprocess
import sys
import time
import uuid
import base64

SUPABASE_URL = "https://zbqhxqnkoggckxoyoqox.supabase.co"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpicWh4cW5rb2dnY2t4b3lvcW94Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg5MzY3ODQsImV4cCI6MjA5NDUxMjc4NH0.RzcpDMMLwux0BFe4H4zSFCgHcIw4JPJSK9fuihI3-Y4"
SERVICE_ROLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpicWh4cW5rb2dnY2t4b3lvcW94Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODkzNjc4NCwiZXhwIjoyMDk0NTEyNzg0fQ.GMYTZzsVT48SY8F3ot2beobTYrojA5NzByaTkUEKBmM"
ADMIN_EMAIL = "umohyeneabasi@gmail.com"
ADMIN_PASS = "Test123!@#"


def decode_jwt(jwt_str):
    parts = jwt_str.split(".")
    if len(parts) != 3:
        return None
    p = parts[1]
    pad = 4 - len(p) % 4
    if pad != 4:
        p += "=" * pad
    try:
        return json.loads(base64.urlsafe_b64decode(p))
    except:
        return None


def curl(method, path, headers=None, body=None, use_default_auth=True):
    args = [
        "curl", "-s", "-w", "\n%{http_code}",
        "-X", method, f"{SUPABASE_URL}/functions/v1{path}",
        "-H", "Content-Type: application/json",
        "-H", f"apikey: {ANON_KEY}",
    ]
    if use_default_auth:
        args += ["-H", f"Authorization: Bearer {ANON_KEY}"]
    if headers:
        for k, v in headers.items():
            args += ["-H", f"{k}: {v}"]
    if body:
        args += ["-d", json.dumps(body)]
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=20)
        out = r.stdout.strip()
        if not out:
            return 0, {"error": "empty"}
        parts = out.rsplit("\n", 1)
        st = int(parts[-1].strip()) if parts[-1].strip().isdigit() else 0
        bd = parts[0].strip() if len(parts) > 1 else ""
        try:
            data = json.loads(bd) if bd else {}
        except:
            data = {"raw": bd}
        return st, data
    except Exception as e:
        return 0, {"error": str(e)}


def sr_rest(method, url_suffix, body=None):
    """Direct REST call using service_role key."""
    args = [
        "curl", "-s", "-w", "\n%{http_code}",
        "-X", method,
        f"{SUPABASE_URL}/rest/v1{url_suffix}",
        "-H", "Accept: application/json",
        "-H", "Content-Type: application/json",
        "-H", f"apikey: {SERVICE_ROLE_KEY}",
        "-H", f"Authorization: Bearer {SERVICE_ROLE_KEY}",
    ]
    if body is not None:
        args += ["-d", json.dumps(body)]
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=15)
        out = r.stdout.strip()
        if not out:
            return 0, []
        parts = out.rsplit("\n", 1)
        st = int(parts[-1].strip()) if parts[-1].strip().isdigit() else 0
        bd = parts[0].strip() if len(parts) > 1 else "[]"
        try:
            data = json.loads(bd) if bd else []
        except:
            data = [{"raw": bd}]
        return st, data
    except:
        return 0, []


def main():
    print("=" * 70)
    print("E2E TEST: sync-push school_id derivation fix")
    print("=" * 70)
    print()

    # STEP 0: Pre-cleanup any leftover test data
    print("--- STEP 0: Pre-cleanup leftover test data ---")
    # Remove any leftover _test_e2e_subject from previous runs
    st, subjects = sr_rest("GET", "/subjects?subject_name=eq._test_e2e_subject&select=id&limit=5")
    if st == 200 and subjects and isinstance(subjects, list):
        for s in subjects:
            sid = s.get("id")
            if sid:
                st_del, _ = sr_rest("DELETE", f"/subjects?id=eq.{sid}")
                print(f"  Pre-cleanup: deleted subject {sid}: status={st_del}")
    # Remove any leftover test lessons
    st, lessons = sr_rest("GET", "/lessons?title=like.*TEST: E2E*&select=id&limit=5")
    if st == 200 and lessons and isinstance(lessons, list):
        for l in lessons:
            lid = l.get("id")
            if lid:
                st_del, _ = sr_rest("DELETE", f"/lessons?id=eq.{lid}")
                print(f"  Pre-cleanup: deleted lesson {lid}: status={st_del}")
    print()

    # STEP 1: Login
    print("--- STEP 1: Login ---")
    st, data = curl("POST", "/login", body={"email": ADMIN_EMAIL, "password": ADMIN_PASS})
    if st != 200:
        print(f"[FATAL] Login failed: {st}")
        return 1
    jwt = data.get("jwt", "")
    claims = decode_jwt(jwt)
    teacher_id = claims.get("teacher_id")
    school_id = claims.get("school_id")
    print(f"  teacher_id : {teacher_id}")
    print(f"  school_id  : {school_id}")
    print(f"  is_admin   : {claims.get('is_admin')}")
    print()

    # STEP 2: Create test subject
    # The subjects table has NOT NULL constraints on:
    #   subject_name, school_id, curriculum (CHECK: nerdc|cambridge|ccss), is_active
    print("--- STEP 2: Create test subject ---")
    test_subject_id = None

    # 2a: Try via sync-push (admin table, handles name->subject_name mapping)
    subject_payload = {
        "changes": [{
            "table": "subjects",
            "operation": "INSERT",
            "rowData": {
                "name": "_test_e2e_subject",
                "school_id": school_id,
                "class_level": "Grade 1",
                "curriculum": "nerdc",
                "is_active": True,
            }
        }]
    }
    st, subj_resp = curl("POST", "/sync-push", headers={"x-classai-jwt": jwt}, body=subject_payload)
    print(f"  sync-push create subject: status={st}")
    if st == 200 and subj_resp.get("success"):
        res = subj_resp.get("results", [])
        if res and res[0].get("status") == "created":
            test_subject_id = res[0].get("server_id")
            print(f"  Created via sync-push: id={test_subject_id}")

    # 2b: Fallback - direct insert via service_role
    if not test_subject_id:
        print(f"  sync-push failed. Trying direct insert via service_role...")
        all_cols = {
            "subject_name": "_test_e2e_subject",
            "school_id": school_id,
            "class_level": "Grade 1",
            "curriculum": "nerdc",
            "is_active": True,
        }
        st3, subj3 = sr_rest("POST", "/subjects", all_cols)
        print(f"  Direct insert: status={st3}")
        if st3 == 201:
            # Fetch the created subject to get its ID
            st4, subjects4 = sr_rest("GET", "/subjects?subject_name=eq._test_e2e_subject&select=id&limit=1")
            if st4 == 200 and subjects4 and isinstance(subjects4, list) and len(subjects4) > 0:
                test_subject_id = subjects4[0].get("id")
                print(f"  Created via direct insert: id={test_subject_id}")

    if not test_subject_id:
        print(f"  [FAIL] All attempts to create subject failed. Aborting.")
        return 1
    print(f"  Test subject id: {test_subject_id}")
    print()

    # STEP 3: Push lesson with WRONG school_server_id
    print("--- STEP 3: Push lesson with WRONG school_server_id ---")
    wrong_school_id = str(uuid.uuid4())
    test_local_id = int(time.time() * 1000) % 1000000
    print(f"  Real school_id (JWT)      : {school_id}")
    print(f"  Wrong school_server_id     : {wrong_school_id}")

    row_data = {
        "local_id": test_local_id,
        "server_id": str(uuid.uuid4()),
        "school_server_id": wrong_school_id,
        "teacher_server_id": teacher_id,
        "subject_id": test_subject_id,
        "topic": "TEST: E2E school_id derivation verification",
        "title": "TEST: E2E school_id derivation verification",
        # Send content as plain text string, not JSON - sync-push
        # will apply LESSON_DEFAULTS for objectives/vocabulary/etc.
        "content": "Verify school_id from JWT. Vocabulary: test. Materials: none.",
        "difficulty": "medium",
        "curriculum": "nerdc",
        "week": 1,
        "week_number": 1,
        "blooms_verbs": "",
        "objectives": "Verify school_id from JWT",
        "vocabulary": "test",
        "materials": "none",
        "presentation": "test",
        "assessment": "test",
        "homework": "none",
        "term": "1",
        "class_level": "Grade 1",
        "status": "draft",
        "is_unlocked": False,
        "update_counter": 0,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

    payload = {"changes": [{"table": "lessons", "operation": "INSERT", "rowData": row_data}]}
    print(f"  Payload rowData keys: {list(row_data.keys())}")
    print(f"  subject_id in payload: {test_subject_id}")

    print(f"  Sending to sync-push...")
    st, sync_data = curl("POST", "/sync-push", headers={"x-classai-jwt": jwt}, body=payload)
    print(f"  status: {st}")
    print(f"  response: {json.dumps(sync_data, indent=2)}")
    print()

    lesson_server_id = None
    result_status = None
    if st == 200 and sync_data.get("success"):
        res = sync_data.get("results", [])
        if res:
            result_status = res[0].get("status")
            lesson_server_id = res[0].get("server_id")
            print(f"  Result: status={result_status}, server_id={lesson_server_id}")

    print()

    # STEP 4: Query stored lesson
    print("--- STEP 4: Query stored lesson ---")
    stored_row = None

    if lesson_server_id:
        st, rows = sr_rest("GET", f"/lessons?id=eq.{lesson_server_id}&select=id,local_id,server_id,school_id,school_server_id,teacher_id,subject_id,title")
        print(f"  By server_id: status={st}, rows={len(rows) if isinstance(rows, list) else 0}")
        if st == 200 and rows and isinstance(rows, list) and len(rows) > 0:
            stored_row = rows[0]

    if not stored_row:
        st, rows = sr_rest("GET", f"/lessons?local_id=eq.{test_local_id}&select=id,local_id,server_id,school_id,school_server_id,teacher_id,subject_id,title")
        print(f"  By local_id: status={st}, rows={len(rows) if isinstance(rows, list) else 0}")
        if st == 200 and rows and isinstance(rows, list) and len(rows) > 0:
            stored_row = rows[0]
            lesson_server_id = stored_row.get("id")

    if not stored_row:
        st, rows = sr_rest("GET", f"/lessons?limit=5&select=id,local_id,server_id,school_id,school_server_id,teacher_id,subject_id,title&order=created_at.desc")
        print(f"  Recent lessons: status={st}, rows={len(rows) if isinstance(rows, list) else 0}")
        if st == 200 and rows and isinstance(rows, list):
            for r in rows[:5]:
                print(f"    id={r.get('id')} title={str(r.get('title',''))[:40]} school_id={r.get('school_id')} local_id={r.get('local_id')}")
            for r in rows:
                if str(r.get("local_id")) == str(test_local_id):
                    stored_row = r
                    lesson_server_id = r.get("id")
                    print(f"  [OK] Found via recent query!")
    print()

    # STEP 5: VERDICT
    print("--- STEP 5: VERDICT ---")
    passed = False

    if stored_row:
        stored_school_id = stored_row.get("school_id", "")
        stored_school_server_id = stored_row.get("school_server_id", "")
        stored_teacher_id = stored_row.get("teacher_id", "")
        stored_subject_id = stored_row.get("subject_id", "")
        print(f"  REFERENCE:")
        print(f"    JWT school_id (authoritative):  {school_id}")
        print(f"    Client-supplied (wrong):        {wrong_school_id}")
        print(f"    Stored school_id:               {stored_school_id}")
        print(f"    Stored school_server_id:        {stored_school_server_id}")
        print(f"    Stored teacher_id:              {stored_teacher_id}")
        print(f"    Stored subject_id:              {stored_subject_id}")
        print(f"    Stored server_id:               {stored_row.get('id')}")
        print()
        if stored_school_id == school_id:
            print(f"  [PASS] school_id matches JWT!")
            if stored_school_id != wrong_school_id:
                print(f"  [PASS] Not the wrong UUID!")
                passed = True
            else:
                print(f"  [FAIL] school_id == wrong UUID! Fix NOT working.")
        else:
            print(f"  [FAIL] school_id={stored_school_id}, expected={school_id}")
            if stored_school_id == wrong_school_id:
                print(f"  [CRITICAL] Wrong school stored! Fix NOT working.")
    elif lesson_server_id:
        print(f"  [FAIL] Lesson server_id={lesson_server_id} but could not fetch row")
    else:
        print(f"  [FAIL] Could not create lesson (sync-push returned error)")
        print(f"  Response: {json.dumps(sync_data, indent=2)}")

    print()

    # STEP 6: CLEANUP
    print("--- STEP 6: CLEANUP ---")
    deleted_ids = []

    if stored_row and stored_row.get("id"):
        lid = stored_row["id"]
        st, d = sr_rest("DELETE", f"/lessons?id=eq.{lid}")
        print(f"  DELETE lesson id={lid}: status={st}")
        deleted_ids.append(lid)

    if lesson_server_id and lesson_server_id not in deleted_ids:
        st, d = sr_rest("DELETE", f"/lessons?id=eq.{lesson_server_id}")
        print(f"  DELETE lesson id={lesson_server_id}: status={st}")
        deleted_ids.append(lesson_server_id)

    # Always cleanup by local_id
    st, d = sr_rest("DELETE", f"/lessons?local_id=eq.{test_local_id}")
    print(f"  DELETE lesson local_id={test_local_id}: status={st}")

    # Delete test subject
    st, d = sr_rest("DELETE", f"/subjects?id=eq.{test_subject_id}")
    print(f"  DELETE subject id={test_subject_id}: status={st}")

    # Verify lesson cleanup
    for lid in deleted_ids:
        st, rows = sr_rest("GET", f"/lessons?id=eq.{lid}&select=id")
        if st == 200 and len(rows) == 0:
            print(f"  [OK] Lesson {lid} confirmed deleted")
        else:
            print(f"  [WARN] Lesson {lid} may not have been deleted (status={st})")

    print()
    print("=" * 70)
    print(f"TEST {'PASSED' if passed else 'FAILED'}")
    print("=" * 70)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
