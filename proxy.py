import subprocess
import time
import uuid
import os
import shlex
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.post("/v1/chat/completions")
async def handle_chat(request: Request):
    try:
        data = await request.json()
    except Exception:
        return JSONResponse(status_code=400, content={"error": "Invalid JSON"})

    messages = data.get("messages", [])
    if not messages:
        return JSONResponse(status_code=400, content={"error": "No messages found"})

    prompt_text = ""
    # Find the last message from the user
    if len(messages) > 0:
        last_message = messages[-1]
        content = last_message.get("content", "")
        if isinstance(content, list):
            text_pieces = [part.get("text") for part in content if part.get("type") == "text"]
            prompt_text = " ".join(text_pieces)
        else:
            prompt_text = content

    # --- AUTOMATIC CHECKPOINT VIA GIT ---
    if os.path.isdir(".git"):  # only try if inside a git repo
        try:
            preview = prompt_text[:40].replace('"', "'") + "..." if len(prompt_text) > 40 else prompt_text.replace('"', "'")
            commit_msg = f"Auto-checkpoint: {preview}"
            subprocess.run(["git", "add", "."], capture_output=True, check=False)
            subprocess.run(["git", "commit", "-m", commit_msg], capture_output=True, check=False)
        except Exception as e:
            print(f"Failed to create Git checkpoint: {e}")
    # ------------------------------------

    # Run the Command Code CLI using the Windows shell so that .cmd files are found
    cmd_string = shlex.join(["command-code", "-p", prompt_text])  # safe joining for shell
    try:
        process = subprocess.run(
            cmd_string,
            capture_output=True,
            text=True,
            check=True,
            shell=True  # <-- this allows cmd.exe to resolve command-code.cmd
        )
        final_output = process.stdout
    except subprocess.CalledProcessError as error:
        final_output = f"Error: {error.stderr}"

    # Make the response look like a real OpenAI server
    reply = {
        "id": f"chatcmpl-{uuid.uuid4()}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": "command-code-proxy",
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": final_output
                },
                "finish_reason": "stop"
            }
        ],
        "usage": {
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "total_tokens": 0
        }
    }

    return JSONResponse(content=reply)

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)