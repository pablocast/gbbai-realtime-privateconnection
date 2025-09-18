from openai import AsyncAzureOpenAI
import json
from fastrtc import (
    AdditionalOutputs,
    AsyncStreamHandler,
    Stream,
    wait_for_item,
    UIArgs
)
import asyncio
import os

SAMPLE_RATE = 24000

SESSION_CONFIG={
    "input_audio_transcription": {
      "model": "whisper-1"
    },
    "turn_detection": {
      "threshold": 0.4,
      "silence_duration_ms": 600,
      "type": "server_vad"
    },
    "instructions": "Your name is Amy. You're a helpful agent who responds initially with a clam British accent, but also can speak in any language as the user chooses to. Always start the conversation with a cheery hello",
    "voice": "shimmer",
    "modalities": ["text", "audio"] ## required to solicit the initial welcome message
    }

def on_open(ws):
    print("Connected to server.")

def on_message(ws, message):
    data = json.loads(message)
    print("Received event:", json.dumps(data, indent=2))

class OpenAIHandler(AsyncStreamHandler):
    def __init__(self) -> None:
        super().__init__(
            expected_layout="mono",
            output_sample_rate=SAMPLE_RATE,
            output_frame_size=480,  # In this example we choose 480 samples per frame.
            input_sample_rate=SAMPLE_RATE,
        )
        self.connection = None
        self.output_queue = asyncio.Queue()

    def copy(self):
        return OpenAIHandler()

    async def welcome(self):
        await self.connection.conversation.item.create( # type: ignore
            item={
                "type": "message",
                "role": "user",
                "content": [{"type": "input_text", "text": "what's your name?"}],
            }
        )
        await self.connection.response.create() # type: ignore

    async def start_up(self):
        """
        Establish a persistent realtime connection to the Azure OpenAI backend.
        The connection is configured for server‐side Voice Activity Detection.
        """
        self.client = openai.AsyncAzureOpenAI(
            azure_endpoint=f"{os.getenv('APIM_RESOURCE_GATEWAY_URL')}/inference",
            azure_deployment=os.getenv("AZURE_OPENAI_DEPLOYMENT_NAME"),
            api_key=os.getenv("API_KEY"),
            api_version=os.getenv("AZURE_OPENAI_API_VERSION"),
        )
        # When using Azure OpenAI realtime (beta), set the model/deployment identifier
        async with self.client.realtime.connect(
            model=os.getenv("AZURE_OPENAI_DEPLOYMENT_NAME")  # Replace with your deployed realtime model id on Azure OpenAI.
        ) as conn:
            # Configure the session to use server-based voice activity detection (VAD)
            await conn.session.update(session=SESSION_CONFIG) # type: ignore
            self.connection = conn

            # Uncomment the following line to send a welcome message to the assistant.
            # await self.welcome()

            async for event in self.connection:
                # Handle interruptions
                if event.type == "input_audio_buffer.speech_started":
                    self.clear_queue()
                if event.type == "conversation.item.input_audio_transcription.completed":
                    # This event signals that an input audio transcription is completed.
                    await self.output_queue.put(AdditionalOutputs(event))
                if event.type == "response.audio_transcript.done":
                    # This event signals that a response audio transcription is completed.
                    await self.output_queue.put(AdditionalOutputs(event))
                if event.type == "response.audio.delta":
                    # For incremental audio output events, decode the delta.
                    await self.output_queue.put(
                        (
                            self.output_sample_rate,
                            np.frombuffer(base64.b64decode(event.delta), dtype=np.int16).reshape(1, -1),
                        ),
                    )

    async def receive(self, frame: tuple[int, np.ndarray]) -> None:
        """
        Receives an audio frame from the stream and sends it into the realtime API.
        The audio data is encoded as Base64 before appending to the connection's input.
        """
        if not self.connection:
            return
        _, array = frame
        array = array.squeeze()
        # Encode audio as Base64 string
        audio_message = base64.b64encode(array.tobytes()).decode("utf-8")
        await self.connection.input_audio_buffer.append(audio=audio_message)  # type: ignore

    async def emit(self) -> tuple[int, np.ndarray] | AdditionalOutputs | None:
        """
        Waits for and returns the next output from the output queue.
        The output may be an audio chunk or an additional output such as transcription.
        """
        return await wait_for_item(self.output_queue)

    async def shutdown(self) -> None: # type: ignore
        if self.connection:
            await self.connection.close()
            self.connection = None

def update_chatbot(chatbot: list[dict], content):
    """
    Append the completed transcription to the chatbot messages.
    """
    if content.type == "conversation.item.input_audio_transcription.completed":
        chatbot.append({"role": "user", "content": content.transcript})
    elif content.type == "response.audio_transcript.done":
        chatbot.append({"role": "assistant", "content": content.transcript})
    return chatbot