"""Minimal OpenHands SDK agent against the campus endpoint.

pip install openhands-sdk openhands-tools
CAMPUS_LLM_URL=... CAMPUS_LLM_MODEL=... CAMPUS_LLM_KEY=... python openhands_sdk_example.py "Fix the failing test"

Every LLM request/response is written to logs/completions — exactly the data
a later fine-tuning run needs (see edu/07-traces-to-fine-tuning.md).
"""

import os
import sys

from openhands.sdk import LLM, Agent, Conversation, Tool
from openhands.tools.file_editor import FileEditorTool
from openhands.tools.terminal import TerminalTool

llm = LLM(
    model=f"openai/{os.environ['CAMPUS_LLM_MODEL']}",
    base_url=os.environ["CAMPUS_LLM_URL"],
    api_key=os.environ.get("CAMPUS_LLM_KEY", "dummy"),
    usage_id="agent",
    native_tool_calling=True,  # False = prompt-based tool calls; compare both in class
    log_completions=True,
    log_completions_folder="logs/completions",
)
agent = Agent(llm=llm, tools=[Tool(name=TerminalTool.name), Tool(name=FileEditorTool.name)])
conversation = Conversation(agent=agent, workspace=".", persistence_dir="runs/")
conversation.send_message(sys.argv[1] if len(sys.argv) > 1 else "Summarize this repository.")
conversation.run()
