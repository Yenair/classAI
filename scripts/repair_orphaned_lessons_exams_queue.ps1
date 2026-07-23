param(
  [Parameter(Mandatory = $true)]
  [string]$DatabasePath
)

$resolvedDbPath = (Resolve-Path -LiteralPath $DatabasePath).Path
$sqlite = (Get-Command sqlite3.exe -ErrorAction Stop).Source

$lessonTeacherServerId = 'f51dce33-3aa8-425a-9c19-c14334a49cfa'
$wrongSchoolServerId = '924744b8-c893-42cb-8fd0-8a3b539957ff'

$beforeQuery = @"
SELECT
  (SELECT COUNT(*)
   FROM lessons
   WHERE teacher_server_id = '$lessonTeacherServerId'
     AND school_server_id = '$wrongSchoolServerId'
     AND is_deleted = 0) AS lessons_to_queue,
  (SELECT COUNT(*)
   FROM exams
   WHERE teacher_server_id = '$lessonTeacherServerId'
     AND school_server_id = '$wrongSchoolServerId'
     AND is_deleted = 0) AS exams_to_queue,
  (SELECT COUNT(*)
   FROM sync_queue
   WHERE queue_table = 'lessons'
     AND record_local_id IN (
       SELECT id
       FROM lessons
       WHERE teacher_server_id = '$lessonTeacherServerId'
         AND school_server_id = '$wrongSchoolServerId'
         AND is_deleted = 0
     )) AS lesson_queue_matches,
  (SELECT COUNT(*)
   FROM sync_queue
   WHERE queue_table = 'exams'
     AND record_local_id IN (
       SELECT id
       FROM exams
       WHERE teacher_server_id = '$lessonTeacherServerId'
         AND school_server_id = '$wrongSchoolServerId'
         AND is_deleted = 0
     )) AS exam_queue_matches;
"@

$repairSql = @"
BEGIN IMMEDIATE;

INSERT INTO sync_queue (
  queue_table,
  record_local_id,
  operation,
  payload
)
SELECT
  'lessons',
  l.id,
  'INSERT',
  json_object(
    'subject', l.subject,
    'classLevel', l.class_level,
    'week', l.week,
    'topic', l.topic,
    'difficulty', l.difficulty,
    'bloomsVerbs', l.blooms_verbs,
    'curriculum', l.curriculum,
    'teacher_server_id', l.teacher_server_id,
    'school_server_id', l.school_server_id,
    'content', l.content,
    'is_unlocked', json(CASE WHEN l.is_unlocked = 1 THEN 'true' ELSE 'false' END),
    'scheme_of_work_id', l.scheme_of_work_id,
    'week_number', l.week_number,
    'term', l.term
  )
FROM lessons AS l
WHERE l.teacher_server_id = '$lessonTeacherServerId'
  AND l.school_server_id = '$wrongSchoolServerId'
  AND l.is_deleted = 0
  AND NOT EXISTS (
    SELECT 1
    FROM sync_queue AS q
    WHERE q.queue_table = 'lessons'
      AND q.record_local_id = l.id
  );

INSERT INTO sync_queue (
  queue_table,
  record_local_id,
  operation,
  payload
)
SELECT
  'exams',
  e.id,
  'INSERT',
  json_object(
    'subject', e.subject,
    'classLevel', e.class_level,
    'topic', e.topic,
    'difficulty', e.difficulty,
    'curriculum', e.curriculum,
    'teacher_server_id', e.teacher_server_id,
    'school_server_id', e.school_server_id,
    'content', e.content,
    'is_unlocked', json(CASE WHEN e.is_unlocked = 1 THEN 'true' ELSE 'false' END),
    'scheme_of_work_id', e.scheme_of_work_id,
    'week_number', e.week_number,
    'term', e.term
  )
FROM exams AS e
WHERE e.teacher_server_id = '$lessonTeacherServerId'
  AND e.school_server_id = '$wrongSchoolServerId'
  AND e.is_deleted = 0
  AND NOT EXISTS (
    SELECT 1
    FROM sync_queue AS q
    WHERE q.queue_table = 'exams'
      AND q.record_local_id = e.id
  );

COMMIT;
"@

Write-Host "Database: $resolvedDbPath"
Write-Host "Pre-check:"
& $sqlite $resolvedDbPath ".headers on" ".mode column" $beforeQuery

Write-Host "Applying repair..."
$repairSql | & $sqlite $resolvedDbPath

Write-Host "Post-check:"
& $sqlite $resolvedDbPath ".headers on" ".mode column" $beforeQuery
