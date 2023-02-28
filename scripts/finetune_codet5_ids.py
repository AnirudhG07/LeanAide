#!/usr/bin/env python
# coding: utf-8

# This is training of a model for generating lists of identifiers in a proof from the statement.

# This is adapted from a notebook for training a CodeT5 model on generating documentation for Ruby code.


from datasets import load_dataset

dataset = load_dataset("json", "rawdata/train_ids.jsonl")
print(dataset)



# The goal for the model is to generate a docstring based on the provided code. 
# 
# Let's now prepare the examples (i.e. code-docstring pairs) for the model. As you might know, Transformer models like BERT, BART, T5 etc. don't expect text as direct input, but rather integers which are called `input_ids` in HuggingFace Transformers. These represent tokens of a certain vocabulary. The model will learn rich contextual embedding vectors for each token, allowing it to get good results.
# 
# In other words, we need to turn the "Code" input from above into `input_ids`, and similarly, we need to turn the "Docstring" output from above into `input_ids`, which will serve as the `labels` for the model.
# 
# In addition, as these models are trained on batches of examples rather than one example at a time, we'll need to pad/truncate both the inputs and labels, such that they are all of the same length. That's why we also will add an `attention_mask` input to the model, such that it knows not to take into account padding tokens when computing attention scores.
# 
# To summarize: 
# * input: code, which is turned into `input_ids` + `attention_mask`
# * output: docstrings, which are turned into `labels` (which are the `input_ids` of the docstrings).
# 
# Below, we define a `preprocess_examples` function, which we can apply on the entire dataset. 


from transformers import RobertaTokenizer

tokenizer = RobertaTokenizer.from_pretrained("Salesforce/codet5-base")

prefix = "Lean Proof-identifiers from Theorem: "
max_input_length = 256
max_target_length = 256

def preprocess_examples(examples):
  # encode the code-docstring pairs
  theorems = examples['theorem']
  ids = examples['ids']
  
  inputs = [prefix + thm for thm in theorems]
  model_inputs = tokenizer(inputs, max_length=max_input_length, padding="max_length", truncation=True)

  # encode the summaries
  labels = tokenizer(ids, max_length=max_target_length, padding="max_length", truncation=True).input_ids

  # important: we need to replace the index of the padding tokens by -100
  # such that they are not taken into account by the CrossEntropyLoss
  labels_with_ignore_index = []
  for labels_example in labels:
    labels_example = [label if label != 0 else -100 for label in labels_example]
    labels_with_ignore_index.append(labels_example)
  
  model_inputs["labels"] = labels_with_ignore_index

  return model_inputs


# Now that we have defined the function, let's call `.map()` on the HuggingFace Dataset object, which allows us to apply this function in batches (by default a batch size of 1,000 is used!) - hence super fast.



dataset = dataset.map(preprocess_examples, batched=True)

# Next, let's set the format to "torch" and create PyTorch dataloaders.

# In[6]:


from torch.utils.data import DataLoader

dataset.set_format(type="torch", columns=['input_ids', 'attention_mask', 'labels'])
train_dataloader = DataLoader(dataset, shuffle=True, batch_size=8)



batch = next(iter(train_dataloader))
print(batch.keys())


# Let's verify an example, by decoding it back into text:


tokenizer.decode(batch['input_ids'][0])




labels = batch['labels'][0]
tokenizer.decode([label for label in labels if label != -100])




from transformers import T5ForConditionalGeneration 
model = T5ForConditionalGeneration.from_pretrained('Salesforce/codet5-base')



loss = model(input_ids=batch['input_ids'], attention_mask=batch['attention_mask'], labels=batch['labels']).loss

print (loss.item())


from torch.optim import AdamW

optimizer = AdamW(model.parameters(), lr=5e-5)

from transformers import get_scheduler

num_epochs = 3
num_training_steps = num_epochs * len(train_dataloader)
lr_scheduler = get_scheduler(
    name="linear", optimizer=optimizer, num_warmup_steps=5000, num_training_steps=num_training_steps
)



import torch

device = torch.device("cuda") if torch.cuda.is_available() else torch.device("cpu")
model.to(device)
print (device)


from tqdm.auto import tqdm

progress_bar = tqdm(range(num_training_steps))

model.train()
for epoch in range(num_epochs):
    for batch in train_dataloader:
        batch = {k: v.to(device) for k, v in batch.items()}
        outputs = model(**batch)
        loss = outputs.loss
        loss.backward()

        optimizer.step()
        lr_scheduler.step()
        optimizer.zero_grad()
        progress_bar.update(1)
    torch.save(model.state_dict(), f"codet5_ids_epoch_{epoch}.pt")

# ## Inference
# 
# Now that we've trained a model, let's test it on some examples from the test set.
model.eval()
import json
with open('rawdata/test_ids.jsonl') as f:
    test_ids = [json.load(line) for line in f]
print ('Test set size:', len(test_ids))

def generate_ids(prompt):
    input_ids = tokenizer.encode(prompt, return_tensors='pt').to(device)
    gen_tokens = model.generate(
        input_ids,
        do_sample=True,
        temperature=0.8,
        num_return_sequences=5,
        max_length=256,
    )
    gen_text = tokenizer.batch_decode(gen_tokens)
    return gen_text

for d in test_ids:
   gens = generate_ids(d['theorem'])
   d['generated'] = gens

with open('rawdata/test_ids_generated.jsonl', 'w') as f:
    for d in test_ids:
        f.write(json.dumps(d) + '\n')

