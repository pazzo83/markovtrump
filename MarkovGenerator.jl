module MarkovGenerator
using JSON
using Base.Iterators
#CONSTS
const ALPHA = "abcdefghijklmnopqrstuvwxyz"
const ALPHA_UPPER = uppercase(ALPHA)
const ABBR_CAPPED = split(join([
           "ala|ariz|ark|calif|colo|conn|del|fla|ga|ill|ind|kan|ky|la|md|mass|mich|minn|miss|mo|mont|neb|nev|okla|ore|pa|tenn|vt|va|wash|wis|wyo", # States
           "u.s",
           "mr|ms|mrs|msr|dr|gov|pres|sen|sens|rep|reps|prof|gen|messrs|col|sr|jf|sgt|mgr|fr|rev|jr|snr|atty|supt", # Titles
           "ave|blvd|st|rd|hwy", # Streets
           "jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec",
           join(ALPHA, '|')],
       '|'), '|')

const ABBR_LOWER = split("etc|v|vs|viz|al|pct", '|')
const EXCEPTIONS = split("U.S.|U.N.|E.U.|F.B.I.|C.I.A.", '|')
const BEGIN = "___BEGIN__"
const END = "___END__"
const DEFAULT_MAX_OVERLAP_RATIO = 0.7
const DEFAULT_MAX_OVERLAP_TOTAL = 15
const DEFAULT_TRIES = 20

export MarkovText, make_sentence

mutable struct Chain
  statesize::Int
  model::Dict{Tuple, Dict{String, Int}}
  begin_cumdist::Vector{Int}
  begin_choices::Vector{String}

  function Chain(corpus::Vector{Vector{SubString{String}}}, statesize::Int)
    model = buildmodel(statesize, corpus)
    ch = new(statesize, model, Int[], String[])
    precompute_begin_state!(ch)
    return ch
  end
end

struct GenSentenceIterator
  chain::Chain
end

function move(chain::Chain, state::Tuple)
  if state == Tuple(repeated(BEGIN, chain.statesize))
    choices = chain.begin_choices
    cumdist = chain.begin_cumdist
  else
    choices = collect(keys(chain.model[state]))
    weights = collect(values(chain.model[state]))
    cumdist = cumsum(weights)
  end

  r = rand() * cumdist[end]
  selection = choices[searchsortedfirst(cumdist, r)]
  return selection
end

Base.eltype(::Type{GenSentenceIterator}) = String
function Base.start(gsi::GenSentenceIterator)
  state = Tuple(repeated(BEGIN, gsi.chain.statesize))
  nextword = move(gsi.chain, state)
  return tuple(nextword, state)
end

Base.done(gsi::GenSentenceIterator, state::Tuple) = state[1] == END

Base.iteratorsize(::Type{GenSentenceIterator}) = Base.SizeUnknown()

function Base.next(gsi::GenSentenceIterator, state::Tuple)
  prevword, currstate = state
  newstate = tuple(currstate[2:end]..., prevword)
  nextword = move(gsi.chain, newstate)
  return prevword, tuple(nextword, newstate)
end

struct MarkovText
  statesize::Int
  parsedsentences::Vector{Vector{SubString{String}}}
  rejoinedtext::String
  chain::Chain
  lasttweetid::Int

  function MarkovText(inputtext::Vector, statesize::Int, lasttweetid::Int)
    parsedsentences = process_tweets(inputtext)
    rejoinedsentences = join(map(wordjoin, parsedsentences), " ")
    chain = Chain(parsedsentences, statesize)
    return new(statesize, parsedsentences, rejoinedsentences, chain, lasttweetid)
  end
end

function clean_string(str::String)
  cleaned_str = replace(str, '\n',  ". ")

  return cleaned_str
end

function is_abbreviation(word::AbstractString)
  clipped = word[1:end-1]
  if in(clipped[1], ALPHA_UPPER)
    if in(lowercase(clipped), ABBR_CAPPED)
      return true
    else
      return false
    end
  else
    if in(clipped, ABBR_LOWER)
      return true
    else
      return false
    end
  end
end

# splitting
function is_sentence_ender(word::AbstractString)
  if in(word, EXCEPTIONS)
    return false
  end
  if in(word[end], ['?', '!'])
    return true
  end
  if length(replace(word, r"[^A-Z]", "")) > 1
    return true
  end
  if word[end] == '.' && ~is_abbreviation(word)
    return true
  end
  return false
end

function split_into_sentences(text::String)
  regmatch = r"([\w\.'’&\]\)]+[\.\?!])([‘’“”'\"\)\]]*)(\s+(?![a-z\-–—]))"
  matches = String[]
  startidx = 1
  for m in eachmatch(regmatch, text)
    if is_sentence_ender(m.captures[1])
      offset = m.offsets[end]
      push!(matches, strip(text[startidx:offset]))
      startidx = offset
    end
  end
  push!(matches, strip(text[startidx:end]))
  return matches
end

wordjoin(a::Vector{S}) where S <: AbstractString = join(a, " ")
split_sentence(sentence::String) = split(sentence, r"\s+")

function process_tweets(tweets::Vector)
  tweet_vec = String[]
  for i in eachindex(tweets)
    if ~get(tweets[i], "is_retweet", false)
      text = get(tweets[i], "text", "")
      append!(tweet_vec, split_into_sentences(text))
    end
  end

  return map(split_sentence, tweet_vec)
end

function buildmodel(statesize::Int, corpus::Vector{Vector{SubString{String}}})
  model = Dict{Tuple, Dict{String, Int}}()

  for i in eachindex(corpus)
    run = corpus[i]
    items = collect(repeated(BEGIN, statesize))
    append!(items, run)
    push!(items, END)

    for j = 1:length(run)+1
      state = Tuple(items[j:j+statesize-1])
      follow = items[j+statesize]
      if ~haskey(model, state)
        model[state] = Dict()
      end
      if ~haskey(model[state], follow)
        model[state][follow] = 0
      end

      model[state][follow] += 1
    end
  end

  return model
end

function precompute_begin_state!(chain::Chain)
  begin_state = Tuple(repeated(BEGIN, chain.statesize))
  choices = collect(keys(chain.model[begin_state]))
  weights = collect(values(chain.model[begin_state]))
  cumdist = cumsum(weights)
  chain.begin_cumdist = cumdist
  chain.begin_choices = choices
  return chain
end

walk(chain::Chain) = collect(GenSentenceIterator(chain))

function test_sentence_output(text::MarkovText, words::Vector{String})
  if length(words) == 1 && (words[1] == "" || startswith(words[1], '@'))
    return false
  end
  max_overlap_ratio = DEFAULT_MAX_OVERLAP_RATIO
  max_overlap_total = DEFAULT_MAX_OVERLAP_TOTAL

  # reject large chunks of similarity
  overlap_ratio = round(Int, max_overlap_ratio * length(words))
  overlap_over = min(max_overlap_total, overlap_ratio)

  gram_count = max((length(words) - overlap_over), 1)
  if gram_count + overlap_over <= length(words)
    grams = [words[i:i+overlap_over] for i = 1:gram_count]
    for g in grams
      gramjoined = wordjoin(g)
      if contains(text.rejoinedtext, gramjoined)
        return false
      end
    end
  end

  return true
end

function make_sentence(text::MarkovText)
  tries = DEFAULT_TRIES
  maxwords = 0
  for _ in 1:tries
    prefix = String[]
    words = vcat(prefix, walk(text.chain))
    if maxwords > 0 && length(words) > maxwords
      continue
    end
    if test_sentence_output(text, words)
      return wordjoin(words)
    end
  end
  return ""
end

function make_sentence(text::MarkovText, maxchars::Int)
  tries = DEFAULT_TRIES
  for _ in 1:tries
    sentence = make_sentence(text)
    if sentence != "" && length(sentence) <= maxchars
      return sentence
    end
  end
  return ""
end

function Base.show(io::IO, text::MarkovText)
  print("Markov MarkovText Object (tweets: $(length(text.parsedsentences)), totaltext: $(length(text.rejoinedtext)) words, statesize: $(text.statesize), lasttweetid: $(text.lasttweetid))")
end

end
