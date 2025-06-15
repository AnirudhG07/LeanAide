import base64
import json
import os

from dotenv import load_dotenv
from openai import OpenAI
import pymupdf
from serv_utils import SCHEMA_JSON
import streamlit as st

from llm_prompts import *

load_dotenv()

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
client = OpenAI(
    api_key  = OPENAI_API_KEY,
)

## Get model list supported by API KEY
def get_openai_models(api_key: str = OPENAI_API_KEY):
    """
    Get the list of models supported by the OpenAI API key.
    """
    client = OpenAI(api_key=api_key)
    models = client.models.list()
    return [model.id for model in models.data]

def get_openai_pdf_id(pdf_path: str):
    file = client.files.create(
        file=open(pdf_path, "rb"),
        purpose="user_data"
    )
    return file

## Images
def encode_image(image_path):
  with open(image_path, "rb") as image_file:
    return base64.b64encode(image_file.read()).decode('utf-8')

def image_solution(image_path: str, model: str = "gpt-4o"):
    image_encoded = encode_image(image_path) 
    gpt_prompt = "Extract text using LaTeX from the given mathematics solution as images. GIVE ONLY THE PROOF within Latex code block."

    response = client.chat.completions.create(
        model=model,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": gpt_prompt,
                    },
                    {
                        "type": "image_url",
                        "image_url": {
                            "url":  f"data:image/jpeg;base64,{image_encoded}"
                        },
                    },
                ],
            }
        ],
        temperature=0.0,
    )

    response_txt = response.choices[0].message.content
    if response_txt is None or response_txt == "":
        return "No response from model while extracting text from image"
    if response_txt:
        response_txt = response_txt.strip("```latex").strip("```")
    return response_txt

def solution_from_images(image_paths, model: str = "gpt-4o"):
    combined_text = ""
    for image_path in image_paths:
        response = image_solution(image_path)
        combined_text += str(response)

    prompt = f"Proof is: {combined_text}"

    return str(gpt_response_gen(soln_from_image_prompt, prompt, model=model))

## PDF
def extract_text_from_pdf(path: str) -> str:
    """Extract text from a PDF file."""
    with pymupdf.open(path) as doc:  # open document
        text = chr(12).join([page.get_text() for page in doc])
    return text

def gpt_response_gen(prompt:str, task:str = "",  model:str ="gpt-4o", json_output: bool = False, json_schema = SCHEMA_JSON, pdf_val = None, paper_input: bool = False):
    """
    GPT response generator function.
    Args:
        prompt (str): The prompt to send to the GPT model.
        task (str): Optional system message to set the context for the model.
        json_output (bool): Whether to format the response as JSON, else text.
        json_schema (dict): The JSON schema to use for the response format.
        model (str): The model to use for generating the response.
        pdf_input (str): Optional text extracted from a PDF to include in the messages.
    """
    messages = []
    if task != "":
        messages.append({
            "role": "system",
            "content": task
        })
    messages.append({
        "role": "user",
        "content": prompt,
    })
    
    ## Case 1. In case of non paper, the pdf/non-pdf content is passed in prompt.
    ## Case 2. In case of paper, the non pdf content is passed in prompt.
    ## Case 3. In case of paper, the pdf_val is the OpenAI File object.
    if type(pdf_val)!= type("") and not paper_input:
        pass # Case 1
    elif type(pdf_val)!= type("") and paper_input: # Case 3
        # pdf_text is not string but OpenAi File object
        pdf_id = pdf_val.id
        messages.append({
            "role": "user",
            "content": {
                "type": "file",
                "file": {
                    "file_id": pdf_id,  
                }
            }
        }) 

    if json_output:
        response = client.chat.completions.create(
                model=model,
                messages=messages,
                response_format= {"type": "json_object"}
                # This wont work for complex schema
                # response_format={
                #     "type": "json_schema",
                #     "json_schema": {
                #         "name": "LeanAide_PaperStructure",
                #         "schema": json_schema,
                #         "strict": True
                #     }
                # }
        ) 
        
    else:
        response = client.chat.completions.create(
            model=model,
            messages=messages,
        )
    if response is None:
        return "No response from model."

    return response.choices[0].message.content

    
def gen_thmpf_json(thm: str, pf: str, model: str = "gpt-4o"):
    response = gpt_response_gen(
        thmpf_prompt(thm, pf),
        json_output = True, 
        model = model
    )
    # response = json.dumps({"x": 1, "y": 2}, indent = 2)  # Placeholder for actual response generation FOR DEBUGGING
    if "no response" in response.lower():
        return {"response" : "No response from model while generating structured proof"}
    response_cleaned = response.strip("```json").strip("```")

    output = json.dumps(json.loads(response_cleaned), indent=2)
    return output

def gen_paper_json(paper_text, pdf_input:bool = False, model: str = "gpt-4o"):
    st.toast(f"Paper text: {paper_text}, PDF input: {pdf_input}")
    response = gpt_response_gen(
        prompt = mathpaper_prompt(paper_text, pdf_input)["prompt"],
        task = mathpaper_prompt(paper_text, pdf_input)["task"],
        json_output=True,
        model=model,
        paper_input=True,
        pdf_val=paper_text, # the File Object goes from here in case of paper
    )
    # response = json.dumps({"x": 1, "y": 2}, indent = 2)  # Placeholder for actual response generation FOR DEBUGGING

    if "no response" in response.lower():
        return {"response" : "No response from model while generating structured proof"}
    response_cleaned = response.strip("```json").strip("```")
    
    return json.dumps(json.loads(response_cleaned), indent=2)

if __name__ == "__main__":
    model = "gpt-4o"
    thm= "The sum of the interior angles of any triangle is 180 degrees."
    pf ="Consider a triangle with vertices $A$, $B$, and $C$. Draw a line parallel to side $BC$ through vertex $A$. By the alternate interior angle theorem, the angles at $B$ and $C$ of the triangle are equal to the corresponding alternate angles formed by the parallel line and the transversal lines $AB$ and $AC$. Since the angles on a straight line sum to $180^\\circ$, the sum of the interior angles of the triangle, $\\angle A + \\angle B + \\angle C$, is $180^\\circ$."
    print(gen_thmpf_json(thm, pf, model=model))