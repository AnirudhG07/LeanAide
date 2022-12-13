import StatementAutoformalisation.Translate
import StatementAutoformalisation.Config.FixedPrompts

def LLMParams : LLM.Params :=
{
  openAIModel := "code-davinci-002",
  temperature := 2,
  n := 1,
  maxTokens := 200,
  stopTokens := #[":=", "\n\n/-", "\n/-", "/-"]
}

def SentenceSimilarityParams : SentenceSimilarity.Params :=
{
  source := "data/prompts.json",
  sentenceTransformersModel := "all-mpnet-base-v2",
  kind := "theorem",
  field := "doc_string",
  nSim := 10
}

def KeywordExtractionParams : KeywordExtraction.Params :=
{
  nKw := 0
}

/-- The expected `kind` (`theorem`/`def`/...) of the completion.
  This variable is required only to modify the suffix of the main prompt. -/
def expectedKind? : Option String := "theorem"

def PromptParams : Prompt.Params :=
{
  toLLMParams := LLMParams, 
  toSentenceSimilarityParams := #[SentenceSimilarityParams], 
  toKeywordExtractionParams := #[KeywordExtractionParams],
  fixedPrompts := leanChatPrompts,
  useNames := #[],
  useModules := #[],
  useMainCtx? := false,
  printDecl := DeclarationWithDocstring.toString
  mkSuffix := fun stmt => s!"{printAsComment stmt}\n{expectedKind?.getD ""}",
  processCompletion := fun comment completion => s!"{printAsComment comment}\n{expectedKind?.getD ""} {completion}"
}
