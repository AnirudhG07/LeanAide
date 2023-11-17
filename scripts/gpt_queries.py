# Note: you need to be using OpenAI Python v0.27.0 for the code below to work
import openai
import os


lean_sys_prompt = """You are a coding assistant who translates from natural language to Lean Theorem Prover code following examples. Follow EXACTLY the examples given"""

sys_prompt = "You are a Mathematics, Lean 4 and coding assistant who translates from natural language to Lean Theorem Prover code following examples, gives hints while coding in Lean 4 and answers questions about Lean 4 and mathematics. Follow EXACTLY the examples given when generating Lean code."


def gpt4t_completions(query, sys_prompt = sys_prompt, examples = [], n= 5):
    messages = [{"role": "system", "content": sys_prompt}] + examples + [{"role": "user", "content": query}]
    completion = openai.ChatCompletion.create(
        model="gpt-4-1106-preview",
        n= n,
        temperature=0.8,
        messages= messages
    )
    # return completion
    return [choice.message['content'].encode().decode('unicode-escape').encode('latin1').decode('utf-8') for choice in completion.choices]

# print([choice.message['content'].encode().decode('unicode-escape').encode('latin1').decode('utf-8') for choice in completion.choices])
