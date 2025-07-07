from transformers import pipeline
import torch
import os
from huggingface_hub import login
from dotenv import load_dotenv
load_dotenv("../../.env")

HUGGING_FACE_TOKEN = os.getenv("HUGGING_FACE_TOKEN")
login(token=HUGGING_FACE_TOKEN)

# For fast download
os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "1"

# snapshot_download(repo_id="google/gemma-3n-e4b-it", repo_type="model")

torch.set_float32_matmul_precision('high')
pipe = pipeline(
    "image-text-to-text",
    model="google/gemma-3n-E4B-it",
    device="cuda",
    torch_dtype=torch.bfloat16,
)

def generate_text(sys_prompt, prompt):
    messages = [
        {
            "role": "system",
            "content": [{"type": "text", "text": sys_prompt}]
        },
        {
            "role": "user",
            "content": [
                {"type": "text", "text": prompt}
            ]
        }
    ]

    output = pipe(text=messages, max_new_tokens=16384, do_sample=False)
    output = output[0]["generated_text"][-1]["content"]
    # only extract inside the json code block
    if output.startswith("```json"):
        output = output.strip("```json").strip("```").strip()
    elif output.startswith("```"):
        output = output.strip("```").strip()
    return output

with open("./hf_prompt.txt", "r") as f:
    sys_prompt = f.read()

long_input = """
Structured JSON is given, make lean code from it and elaborate it. 
```json
{
  "document": [
    {
      "type": "Section",
      "label": "sec:assumptions",
      "header": "Assumptions",
      "level": 1,
      "content": [
        {
          "type": "let_statement",
          "variable_name": "G",
          "variable_type": "type equipped with group structure (G, ·_G, e_G, inv_G)",
          "statement": "Let G be a type equipped with group structure (G, ·_G, e_G, inv_G)."
        },
        {
          "type": "let_statement",
          "variable_name": "H",
          "variable_type": "type equipped with group structure (H, ·_H, e_H, inv_H)",
          "statement": "Let H be a type equipped with group structure (H, ·_H, e_H, inv_H)."
        },
        {
          "type": "assume_statement",
          "assumption": "φ : G ≃_{Grp} H is a group isomorphism."
        },
        {
          "type": "assume_statement",
          "label": "h_comm",
          "assumption": "∀ g1 g2 : G, g1 ·_G g2 = g2 ·_G g1."
        }
      ]
    },
    {
      "type": "Definition",
      "label": "def:phi_hom",
      "header": "Definition",
      "definition": "Let φ_hom : G → H denote the underlying group homomorphism of φ. By definition of group isomorphism, φ_hom is bijective and satisfies ∀ g1, g2 : G, φ_hom(g1 ·_G g2) = φ_hom(g1) ·_H φ_hom(g2)."
    },
    {
      "type": "Definition",
      "label": "def:phi_inv",
      "header": "Definition",
      "definition": "Let φ_inv : H → G denote the inverse function of the bijection φ_hom. Then for all h : H, φ_hom(φ_inv(h)) = h and φ_inv(φ_hom(g)) = g."
    },
    {
      "type": "Theorem",
      "label": "thm:H-abelian",
      "header": "Theorem",
      "claim": "∀ x y : H, x ·_H y = y ·_H x.",
      "proof": {
        "type": "Proof",
        "claim_label": "thm:H-abelian",
        "proof_steps": [
          [
            {
              "type": "let_statement",
              "variable_name": "x",
              "variable_type": "element of H",
              "statement": "Let x be an arbitrary element of H."
            },
            {
              "type": "let_statement",
              "variable_name": "y",
              "variable_type": "element of H",
              "statement": "Let y be an arbitrary element of H."
            },
            {
              "type": "let_statement",
              "variable_name": "g1",
              "value": "φ_inv(x)",
              "statement": "Define g1 := φ_inv(x)."
            },
            {
              "type": "let_statement",
              "variable_name": "g2",
              "value": "φ_inv(y)",
              "statement": "Define g2 := φ_inv(y)."
            },
            {
              "type": "assert_statement",
              "claim": "φ_hom(g1) = x",
              "internal_references": [
                {
                  "target_identifier": "def:phi_hom"
                }
              ]
            },
            {
              "type": "assert_statement",
              "claim": "φ_hom(g2) = y",
              "internal_references": [
                {
                  "target_identifier": "def:phi_hom"
                }
              ]
            },
            {
              "type": "assert_statement",
              "claim": "x ·_H y = φ_hom(g1 ·_G g2)",
              "internal_references": [
                {
                  "target_identifier": "def:phi_hom"
                }
              ]
            },
            {
              "type": "assert_statement",
              "claim": "g1 ·_G g2 = g2 ·_G g1",
              "internal_references": [
                {
                  "target_identifier": "h_comm"
                }
              ]
            },
            {
              "type": "assert_statement",
              "claim": "φ_hom(g1 ·_G g2) = y ·_H x",
              "calculation": {
                "calculation_sequence": [
                  "φ_hom(g1 ·_G g2) = φ_hom(g2 ·_G g1)",
                  "φ_hom(g2 ·_G g1) = φ_hom(g2) ·_H φ_hom(g1)",
                  "φ_hom(g2) ·_H φ_hom(g1) = y ·_H x"
                ]
              },
              "internal_references": [
                {
                  "target_identifier": "def:phi_hom"
                }
              ]
            },
            {
              "type": "conclude_statement",
              "claim": "Therefore, x ·_H y = y ·_H x."
            }
          ]
        ]
      }
    }
  ]
}

```
"""

# prompt = "Generated detailed theorem translation for theorem, '1+1 = 2'"
if __name__ == "__main__":
    print(generate_text(sys_prompt, long_input))
