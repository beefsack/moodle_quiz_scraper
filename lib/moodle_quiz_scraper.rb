require 'rubygems'
require 'nokogiri'
require 'curb'
require 'yaml'
require 'sanitize'

# FUNCTIONS
def submit_form(form, options = {})
  options[:curl] = Curl::Easy.new if options[:curl].nil?
  options[:params] = {} if options[:params].nil?
  options[:action] = form["action"] if options[:action].nil?
  # Get the form inputs and action
  form.search('input[name]').each do |input|
    options[:params][input["name"]] = input["value"] if options[:params][input["name"]].nil?
  end
  # Build params
  params = []
  options[:params].each_pair do |key, value|
    params.push(Curl::PostField.content(key, value))
  end
  # Request
  options[:curl].url = options[:action]
  options[:curl].http_post(*params)
  return options[:curl]
end

# INIT

warn "Initialising"

username = 'insert_user'
password = 'insert_pass'
form_page = 'https://login.une.edu.au/login?service=http%3A%2F%2Fmoodle.une.edu.au%2Flogin%2Findex.php%3FauthCAS%3DCAS'
form_action = 'https://login.une.edu.au/login?service=http%3A%2F%2Fmoodle.une.edu.au%2Flogin%2Findex.php%3FauthCAS%3DCAS'
#quiz_page = 'http://moodle.une.edu.au/mod/quiz/view.php?id=178243' # MM105 quiz 1
quiz_page = 'http://moodle.une.edu.au/mod/quiz/view.php?id=178420' # MM105 quiz 2
#quiz_page = 'http://moodle.une.edu.au/mod/quiz/view.php?id=178421' # MM105 quiz 3
#quiz_page = 'http://moodle.une.edu.au/mod/quiz/view.php?id=178422' # MM105 quiz 4
#quiz_page = 'http://moodle.une.edu.au/mod/quiz/view.php?id=178423' # MM105 quiz 5
#quiz_page = 'http://moodle.une.edu.au/mod/quiz/view.php?id=180581' # MM105 quiz 6
#quiz_page = 'http://moodle.une.edu.au/mod/quiz/view.php?id=180584' # MM105 quiz 7
#quiz_page = 'http://moodle.une.edu.au/mod/quiz/view.php?id=180587' # MM105 quiz 10
#quiz_page = 'http://moodle.une.edu.au/mod/quiz/view.php?id=180592' # MM105 quiz 11
#quiz_page = 'http://moodle.une.edu.au/mod/quiz/view.php?id=180615' # MM105 quiz 13
passes = 10

c = Curl::Easy.new
c.follow_location = true
#c.verbose = true
c.enable_cookies = true

# GET FORM DATA AND LOGIN

warn "Getting login form"
c.url = form_page
c.http_get
doc = Nokogiri::HTML(c.body_str)
warn "Logging in"
form = doc.search('form#fm1').first
raise "Unable to find login form" if form.nil?
submit_form(form, :action => form_action, :curl => c, :params => {
  "username" => username,
  "password" => password
})

questions = {}

(1..passes).each do |pass|
  
  warn "Performing pass #{pass} of #{passes}"

  # OPEN THE QUIZ
  # .quizstartbuttondiv form
  # POST http://moodle.une.edu.au/mod/quiz/startattempt.php
  # cmid = load from form
  # sesskey = load from form
  
  warn "Opening the quiz"
  c.url = quiz_page
  c.http_get
  doc = Nokogiri::HTML(c.body_str)
  form = doc.search(".quizstartbuttondiv form").first
  raise "Unable to find the start quiz button" if form.nil?
  submit_form(form, :curl => c)
  doc = Nokogiri::HTML(c.body_str)
  
  # ATTEMPT ALL THE QUESTIONS
  # #responseform form
  # POST http://moodle.une.edu.au/mod/quiz/processattempt.php enctype=multipart/form-data
  # Questions all .que
  #		content in .qtext
  #		all answers inside labels in .answer
  # Many hidden inputs, load all from page
  
  question_page_count = 0
  question_count = 0
  while doc.search('form#responseform').length > 0 do
    warn "Parsing question page #{question_page_count += 1}"
    form = doc.search('form#responseform').first
    form.search('.que').each do |question_div|
      # Question text
      warn "Parsing question #{question_count += 1}"
      question_text_div = question_div.search('.qtext').first
      next if question_text_div.nil?
      question = Sanitize.clean(question_text_div.content).strip
      # Answers
      choices = []
      question_div.search('.answer label').each do |answer_div|
        choices.push(Sanitize.clean(answer_div.content).strip)
      end
      questions[question] = {
        :question => question,
        :choices => choices
      }
      warn "Found question: #{question}\n\n#{choices.join("\n")}"
    end
    submit_form(form, :curl => c)
    doc = Nokogiri::HTML(c.body_str)
  end
  
  # CONTINUE THROUGH THE RESULT
  # There is no more #responseForm
  # We have a submit button with value=Submit all and finish
  # Form is contained in .singlebutton and has multiple hidden inputs
  warn "Questions finished, submitting attempt"
  form = doc.search('.singlebutton form').first
  raise "Unable to find attempt submit button" if form.nil?
  submit_form(form, :curl => c)
  doc = Nokogiri::HTML(c.body_str)
  
  # GET RESULTS
  # .questionflagsaveform form
  # Once again questions all .que
  #		content in .qtext
  #		correct answer as label in .answer//.correct
  # Next page as .submitbtns//a href
  answer_page_count = 0
  answer_count = 0
  while doc.search('form.questionflagsaveform').length > 0 do
    warn "Parsing answer page #{answer_page_count += 1}"
    form = doc.search('form.questionflagsaveform').first
    form.search('.que').each do |question_div|
      # Question text
      warn "Parsing answer #{answer_count += 1}"
      question_text_div = question_div.search('.qtext').first
      next if question_text_div.nil?
      question = Sanitize.clean(question_text_div.content).strip
      # Answer
      answer_div = question_div.search('.answer .correct label').first
      if !answer_div.nil?
        answer = Sanitize.clean(answer_div.content).strip
        questions[question][:answer] = answer
        warn "Found answer: #{question}\n\n#{answer}"
      elsif questions[question][:choices].length == 2
        answer = questions[question][:choices].last
        questions[question][:answer] = answer
        warn "No correct answer found but only two choices, assuming second choice: #{question}\n\n#{answer}"
      end
      # Feedback
      feedback_div = question_div.search('.feedback').first
      if !feedback_div.nil?
        feedback = Sanitize.clean(feedback_div.content).strip
        questions[question][:feedback] = feedback
        warn "Found feedback: #{feedback}"
      end
    end
    submit_button = doc.search('.submitbtns a').first
    raise "Unable to find the next button" if submit_button.nil?
    c.url = submit_button["href"]
    c.http_get
    doc = Nokogiri::HTML(c.body_str)
  end
  warn "Finished parsing answers"
  
end

warn "Done!"
puts YAML::dump(questions.values)
exit 0
