# Make a graph from Moeen Dict that connects each word to the nouns in its definition
using FileIO, JLD2
using PyCall
using ProgressMeter
using DataStructures
@pyimport igraph
@pyimport hazm

normalizer = hazm.Normalizer()
stemmer = hazm.Stemmer()
tagger = hazm.POSTagger(model="../data/resources/postagger.model")

const moeen_file = "../data/moeen_ANSI.txt"

"
Parse every entry in the dictionary file. Choose
the Noun stems from the definition and write it all to file.
"
function parse_dict(moeen_file)
	moeen_dict = Dict{AbstractString, Array}()
	prog = ProgressMeter.Progress(32781)
	for line in eachline(open(moeen_file))
		if !startswith(line, "#")
			word, def = split(line, "\t")
			# word = String(word)
			word_tag = tagger[:tag]([word])[1][2]
			def = strip(def)
			def_2 = IOBuffer()
			inpar = false
			for i in def
				if i == '(' || i == '['
					inpar = true
				elseif i == ')' || i == ']'
					inpar = false
				elseif inpar == false
					print(def_2, i)
				end
			end
			# def = takebuf_string(def_2)
			def = String(take!(def_2))
			all_defs = split(def, r"\d")
			final_list = Array{AbstractString}(0)
			for (index, item) in enumerate(all_defs)
				item2 = replace(item, r"\w+", "")
				item2 = strip(item2, ['\n', '<', '>', '.', '-', ' '])
				if length(item2) > 1
					# item2 = strip(convert(UTF8String,item))
					item3 = normalizer[:normalize](item2)
					words = hazm.word_tokenize(item3)
					for (ind, w) in enumerate(words)
						words[ind] = stemmer[:stem](w)
					end
					new_words = Array{AbstractString}(0)
					for (indd, itt) in enumerate(words)
						if length(itt) > 0
							push!(new_words, itt)
						end
					end
					tagged_words = tagger[:tag](new_words)
					for tw in tagged_words
						if tw[2] == "N"
							push!(final_list, tw[1])
						end
					end
				end
			end
			moeen_dict[word] = final_list
		end
		next!(prog)
	end
	# writing the moeen_dict to file
	save("moeen_dict_parsed.jld2", "dict", moeen_dict)
end

function add_edges_to_graph!(yourDict, yourGraph)
	prog = ProgressMeter.Progress(length(yourDict))
	for (k, v) in yourDict
		for i in v
			if length(i) > 1
				yourGraph[:add_edge](k, i)
			end
		end
		next!(prog)
	end
	return yourGraph
end

function dict_to_graph(;jldFile::AbstractString="moeed_dict_parsed.jld2")
	# read back the jld file
	moeen_dict = load(jldFile, "dict")
	# write all definition entries into a single array
	def_values = Array{AbstractString}(0)
	for v in values(moeen_dict)
		for i in v
			push!(def_values, i)
		end
	end
	# add the dict entries to the above array
	for k in keys(moeen_dict)
		push!(def_values, k)
	end
	# make a graph file
	g = igraph.Graph()
	g[:add_vertices](def_values)
	# adding the edges. Not that this part takes very long
	g = add_edges_to_graph!(moeen_dict, g)
	# write the graph to file
	g[:write]("moeen.graph", format="pickle")
	return g
end


function neighbor_dict(g::PyCall.PyObject, moeen_file)
	#=
	g is the graph file created in dict_to_graph
	This function creates a new dictionary from the graph, where each key has
	values from all of its second degree neighbors
	=#
	# a list of moeen dict entries.
	dict_entries = Array{AbstractString}(0)
	for line in eachline(open(moeen_file))
		if !startswith(line, "#")
			word, def = split(line, "\t")
			# word = convert(UTF8String, word)
			push!(dict_entries, word)
		end
	end
	outfile = "moeen_graph_neighbors.txt"
	prog = ProgressMeter.Progress(g[:vcount]())
	open(outfile,"a") do myfile
		for v in g[:vs]
			vname = get(v, "name")
			if in(vname, dict_entries)
				for def in v[:neighbors]()
					second_neighbors = def[:neighbors]()
					second_neighbor_names = Array{AbstractString}(length(second_neighbors))
					for (ind, i) in enumerate(second_neighbors)
						second_neighbor_names[ind] = get(i, "name")
					end
					splice!(second_neighbor_names, findin(second_neighbor_names, [vname])[1])
					result = join([string("(",get(def, "name"), ")"), join(second_neighbor_names, ',')], ";")
					write(myfile, join([vname,result], '\t'))
					write(myfile, "\n")
				end
			end
			next!(prog)
		end
	end
end

function cleandict(;f="moeen_graph_neighbors.txt")
	black_list = ["بودن", "نمودن", "دادن", "شدن", "کردن", "کنایه","افکندن", "<br>", "اس"]
	word_entry = DefaultDict(AbstractString, Set{AbstractString}, Set{AbstractString})
	entry_def = DefaultDict(AbstractString, Set{AbstractString}, Set{AbstractString})
	entry_count = DefaultDict(AbstractString, Integer, 0)

	println("Cleaning the dictionary file...")
	nlines = parse(Int, split(readstring(`wc -l $f`))[1])
	prog = ProgressMeter.Progress(nlines)
	for line in eachline(open(f))
		fields = split(strip(line),"\t")
		word, defin = fields
		entry = split(defin, ";")[1][2:end-1]
		deff = split(defin, ";")[2]
		definitions = split(deff, ",")
		if !in(entry, black_list) && !in(word, black_list)
			push!(word_entry[word], entry)
			for item in definitions
				if !in(item, black_list)
					push!(entry_def[entry], item)
				end
			end
			entry_count[entry] += 1
		end
		next!(prog)
	end

	outfile = "moeen_graph_neighbors_cleaned.txt"
	open(outfile, "a") do f
		prog = ProgressMeter.Progress(length(entry_def))
		written_list = Set{AbstractString}()
		for (entry, definitions) in entry_def
			defs = collect(definitions)
			pass = false
			if length(defs) > 1
				pass = true
			elseif length(defs) == 1
				if length(defs[1]) > 1
					pass = true
				end
			end
			if pass
				if entry_count[entry] > 1
					line = "$entry\tهر یک از این معنی‌ها را ببینید: $(join([i for i in defs], ","))"
					println(f, line)
					push!(written_list, entry)
				end
			end
			next!(prog)
		end
		prog = ProgressMeter.Progress(length(word_entry))
		for (word, entries) in word_entry
			for entry in entries
				if length(entry_def[entry]) > 1
					if entry_count[entry] == 1
						line = "$word\t($entry);$(join([i for i in entry_def[entry]], ","))"
						println(f, line)
					elseif entry_count[entry] > 1 && !in(word, written_list)
						line = "$word\t$entry را ببینید"
						println(f, line)
					end
				end
			end
			next!(prog)
		end
	end


	### remove duplicate keys from the final dictionary file, so that I can make a glossary with stardict.
	f = "moeen_graph_neighbors_cleaned.txt"
	outfile = "moeen_graph_neighbors_cleaned_noDuplicates.txt"
	all_keys = Set()
	open(outfile, "a") do fff
		for line in eachline(open(f))
			fields = split(strip(line), '\t')
			if in(fields[1], all_keys)
				counter = 1
				j1 = fields[1]*string(counter)
				passed = false
				while ~passed
					if ~in(j1, all_keys)
						passed = true
					else
						counter += 1
						j1 = fields[1]*string(counter)
					end
				end
				fields[1] = j1
				push!(all_keys, fields[1])
			end
			println(fff, join(fields, '\t'))
			push!(all_keys, fields[1])
		end
	end

end

function main()
	println("Creating an initial dictionary from file...")
	parse_dict(moeen_file)
	println("Creating a graph...")
	g = dict_to_graph()
	println("Creating adding new connections...")
	neighbor_dict(g, moeenfile)
	println("Cleaning the new dict file...")
	cleandict()
end