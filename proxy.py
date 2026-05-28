import subprocess
import time
import uuid
import os
import json
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
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

@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [
            {
                "id": "command-code-proxy",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "local-proxy"
            }
        ]
    }

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
    if len(messages) > 0:
        last_message = messages[-1]
        content = last_message.get("content", "")
        if isinstance(content, list):
            text_pieces = [
                part.get("text") for part in content if part.get("type") == "text"
            ]
            prompt_text = " ".join(text_pieces)
        else:
            prompt_text = content

    # Optional Git checkpoint
    if os.path.isdir(".git"):
        try:
            preview = prompt_text[:40].replace('"', "'") + "..." if len(prompt_text) > 40 else prompt_text.replace('"', "'")
            subprocess.run(["git", "add", "."], capture_output=True, check=False)
            subprocess.run(["git", "commit", "-m", f"Auto-checkpoint: {preview}"], capture_output=True, check=False)
        except Exception as e:
            print(f"Git checkpoint failed: {e}")

    # --- Truncate prompt to avoid "command line too long" ---
    MAX_PROMPT_LENGTH = 500
    if len(prompt_text) > MAX_PROMPT_LENGTH:
        prompt_text = prompt_text[:MAX_PROMPT_LENGTH] + "... [truncated]"

    # Run command-code
    cmd_list = ["command-code", "-p", prompt_text]
    try:
        process = subprocess.run(cmd_list, capture_output=True, text=True, check=True, shell=True)
        final_output = process.stdout
    except subprocess.CalledProcessError as error:
        final_output = f"Error: {error.stderr}"

    stream = data.get("stream", False)

    if stream:
        async def event_stream():
            chunk = {
                "id": f"chatcmpl-{uuid.uuid4()}",
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": "command-code-proxy",
                "choices": [
                    {
                        "index": 0,
                        "delta": {"content": final_output},
                        "finish_reason": None
                    }
                ]
            }
            yield f"data: {json.dumps(chunk)}\n\n"
            final_chunk = {
                "id": f"chatcmpl-{uuid.uuid4()}",
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": "command-code-proxy",
                "choices": [
                    {
                        "index": 0,
                        "delta": {},
                        "finish_reason": "stop"
                    }
                ]
            }
            yield f"data: {json.dumps(final_chunk)}\n\n"
            yield "data: [DONE]\n\n"

        return StreamingResponse(event_stream(), media_type="text/event-stream")
    else:
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