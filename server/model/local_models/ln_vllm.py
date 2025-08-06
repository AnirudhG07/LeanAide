# main_vllm.py

from vllm import LLM, SamplingParams
from transformers import AutoProcessor
import torch
import os
from huggingface_hub import login
from dotenv import load_dotenv
import time

# --- 1. Environment and Token Setup ---
# Load environment variables from a .env file
load_dotenv("../../../.env")

# Login to Hugging Face Hub
HUGGING_FACE_TOKEN = os.getenv("HUGGING_FACE_TOKEN")
if HUGGING_FACE_TOKEN:
    login(token=HUGGING_FACE_TOKEN)
else:
    print("Warning: Hugging Face token not found. Public models will still work.")

# Enable fast model downloads
os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "1"

# Set PyTorch precision for performance
torch.set_float32_matmul_precision('high')

# --- 2. Model and Processor Loading ---
model_id = "google/gemma-3n-E4B-it"

print("Loading vLLM engine...")
# Load the model using the vLLM engine
# vLLM handles device mapping automatically (GPU if available)
llm = LLM(
    model=model_id,
    trust_remote_code=True, # Recommended for many newer models
    dtype="bfloat16",       # Corresponds to torch.bfloat16
    gpu_memory_utilization=0.95 # Adjust if you have other processes on the GPU
)
print("vLLM engine loaded.")

# We still need the processor, but only to format the chat template
print("Loading tokenizer/processor for chat template...")
processor = AutoProcessor.from_pretrained(model_id)
print("Processor loaded.")


def generate_text_vllm(sys_prompt, user_prompt, llm_engine, proc):
    """
    Generates text using the vLLM engine after formatting the prompt correctly.
    """
    messages = [
        {
            "role": "system",
            "content": [{"type": "text", "text": sys_prompt}]
        },
        {
            "role": "user",
            "content": [
                {"type": "text", "text": user_prompt}
            ]
        }
    ]

    # Apply the chat template to get the full, formatted prompt string
    # IMPORTANT: tokenize=False is crucial as vLLM handles tokenization internally.
    full_prompt = proc.apply_chat_template(
        messages,
        add_generation_prompt=True,
        tokenize=False
    )

    # Define sampling parameters for the generation
    # temperature=0 and top_p=1 is equivalent to do_sample=False (greedy decoding)
    # max_tokens is equivalent to max_new_tokens
    sampling_params = SamplingParams(temperature=0, top_p=1, max_tokens=2048)

    # Generate text in a batch (even with a single prompt)
    outputs = llm_engine.generate([full_prompt], sampling_params)

    # The output is a list of RequestOutput objects.
    # We get the text from the first result's first choice.
    generated_text = outputs[0].outputs[0].text
    
    # --- 4. Output Cleanup (same as original) ---
    if generated_text.startswith("```json"):
        generated_text = generated_text.strip("```json").strip("```").strip()
    elif generated_text.startswith("```"):
        generated_text = generated_text.strip("```").strip()
        
    return generated_text


if __name__ == "__main__":
    # --- 3. Prompt Preparation ---
    try:
        with open("./prompt_intent.md", "r") as f:
            sys_prompt = f.read()
    except FileNotFoundError:
        print("Error: `prompt_intent.md` not found. Please create it with the system prompt.")
        exit()

    # The long JSON input from the original script
    print("\n--- Generating Response ---")
    start_time = time.time()

    user_prompt = "Generate translated lean code for the structured JSON."

    output = generate_text_vllm(sys_prompt, user_prompt, llm, processor)

    end_time = time.time()
    print(output)
    print("---")
    print(f"Time taken: {end_time - start_time:.2f} seconds")
