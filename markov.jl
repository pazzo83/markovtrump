using MarkovGenerator

function main()
  files = ["/Users/christopheralexander/Julia/markovtrump/2012.json",
          "/Users/christopheralexander/Julia/markovtrump/2013.json",
          "/Users/christopheralexander/Julia/markovtrump/2014.json",
          "/Users/christopheralexander/Julia/markovtrump/2015.json",
          "/Users/christopheralexander/Julia/markovtrump/2016.json",
          "/Users/christopheralexander/Julia/markovtrump/2017.json"]
  tweets = []
  latestid = ""
  for f in files
    t = JSON.parsefile(f, dicttype=Dict, use_mmap=true)
    latestid = t[1]["id_str"]
    append!(tweets, t)
  end
  text = MarkovText(tweets, 3, parse(Int, latestid))
  # blah = make_sentence(text)
  return text
end
