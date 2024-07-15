import os
from os.path import join
from pathlib import Path
from .queries import extract_json_block

import vertexai
from vertexai.generative_models import GenerativeModel, Part

homedir = Path(".")
if "lakefile.lean"  not in os.listdir(homedir):
    homedir = Path("..")

resources = join(homedir, "resources")
results = join(homedir, "results")

project_id = os.environ['PROJECT_ID']

model = GenerativeModel("gemini-1.5-pro-001")

vertexai.init(project=project_id, location="asia-south1")

def solution_from_image(image_path):
    response = model.generate_content([
          "Extract text with LaTeX from the following mathematics solution",
          Part.from_uri(f"gs://leanaide/{image_path}", mime_type="image/png"),
          "Also, rewrite the extracted text as a clean mathematical proof with full sentences, conjuctions etc"])
    return response.text

proof_json = open(join(resources, "ProofJsonShorter.md")).read()

def structure_prompt(thm, pf):
    return f"{proof_json}\n---\n\n## Theorem: {thm}\n\n## Proof: {pf}\n"

def structured_proof(thm, pf):
    response = model.generate_content([
        structure_prompt(thm, pf)
    ])
    return extract_json_block(response.text)

def structured_proof_from_image(thm, path):
    pf = solution_from_image(path)
    return pf, structured_proof(thm, pf)

from google.cloud import storage
client = storage.Client()
bucket = client.bucket('leanaide')
def images_in_gs(prefix):
    blobs = client.list_blobs('leanaide', prefix=prefix)    
    return [blob.name for blob in blobs if blob.content_type == 'image/png']

def solutions_from_images(thm, prefix):
    image_paths = images_in_gs(prefix)
    triples = []
    for path in image_paths:
        pf, structured = structured_proof_from_image(thm, path)
        triples.append((path, pf, structured))
    return triples

import pathlib, json
gemini_results = join(results, "gemini_results")
pathlib.Path(gemini_results).mkdir(parents=True, exist_ok=True)

def write_structured_proofs(prefix):
    thm_blob = bucket.blob(f"{prefix}theorem.md")
    with thm_blob.open("r") as f:
        thm = f.read()
    triples = solutions_from_images(thm, prefix)
    for triple in triples:
        path, pf, structured = triple
        with open(join(gemini_results, path.replace("/", "_").replace(".png", ".json")), "w") as f:
            json.dump(structured, f, ensure_ascii=False, indent=2)
        with open(join(gemini_results, path.replace("/", "_").replace(".png", "_sol.md")), "w") as f:
            f.write(f"## Theorem: {thm}\n\n## Proof: {pf}")

# thm = "The map $p \colon \mathbb{R}^2 \to X$, defined by $p(x,y) = (x, y^2)$, is a covering map, where $X = \{(x,y) \in \mathbb{R}^2 : y \ge 0\}$."

# structured, pf = structured_proof_from_image(thm, "mainak-1.png")
# print(pf)
# print(structured)