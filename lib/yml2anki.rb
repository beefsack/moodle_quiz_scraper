require 'yaml'
require 'cgi'

separator = "\t"
separator_replace = "    "

input = ""
ARGF.each do |line|
  input += line
end

questions = YAML::load(input)
questions.each do |question|
  question_output = CGI.escapeHTML(question[:question].gsub(separator, separator_replace))
  if question[:choices]
    question_output += "\n\n" + CGI.escapeHTML(question[:choices].join("\n"))
  end
  question_output += separator
  answer_output = []
  if question[:answer]
    answer_output.push(CGI.escapeHTML(question[:answer].gsub(separator, separator_replace)))
  end
  if question[:feedback]
    answer_output.push(CGI.escapeHTML(question[:feedback].gsub(separator, separator_replace)))
  end
  question_output += answer_output.join("\n")
  puts question_output.gsub("\n", "<br>")
end