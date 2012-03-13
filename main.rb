require 'rubygems'
require 'sinatra'
require 'em-synchrony'
require 'twilio-rb'
require 'mongo_mapper'
require 'logger'
require './model'

EM.synchrony do
  Twilio::Config.setup account_sid: ENV['SID'], auth_token:  ENV['AUTH_TOKEN']

  helpers do
    def protected!
      unless authorized?
        response['WWW-Authenticate'] = %(Basic realm="SXSpotify Admin")
        throw(:halt, [401, "Not authorized\n"])
      end
    end

    def authorized?
      @auth ||=  Rack::Auth::Basic::Request.new(request.env)
      @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == [ENV['ADMIN_USER'], ENV['ADMIN_PASSWORD']]
    end
  end

  before { protected! unless request.path_info == "/sms" }

  # This is our Twilio number
  BROADCASTERS = ['+14158305533', '+14156022729', '+16463340760', '+16464131271'].freeze
  LOGGER       = Logger.new STDOUT

  get '/admin' do
    haml :admin
  end

  post '/admin' do
    User.all(on: true).each do |user|
      retry_count = 0
      begin
        Twilio::SMS.create(from: ENV['CALLER_ID'], to: user[:number], body: params['sms_body']) unless retry_count > 3
      rescue => e
        retry_count += 1
        LOGGER.error "ERROR: failed to send message to #{user[:number]}. Error msg: #{e.to_s}. Retrying #{ 3 - retry_count } more times."
        retry
      end

    end

    count = User.count on: true

    BROADCASTERS.each do |number|
      Twilio::SMS.create from: ENV['CALLER_ID'], to: number, body: 'INFO: Message sent to ' + count.to_s + ' subscribers from web interface.'
    end

    LOGGER.info "Broadcast sent. Message body: #{params[:sms_body]}"

    "Message sent."
  end

  # When someone sends a text message to us, this code runs
  post '/sms' do

    # Break down the message object into usable variables
    from = params['From'] # The @from variable is the user's cell phone number
    body = params['Body'] # The body of the text message
    on   = false # Whether or not the user wants texts

    # If a phone number is not in the database, create a row in the database.
    user = User.first(number: from) || User.create(number: from, on: on)

    case body
    when /^subscribe$/i, /^spotify$/i, /^join$/i
      message = 'Welcome! You will now get updates from Spotify about awesome events in Austin next week. Text "off" to unsubscribe. SMS powered by Twilio!'
      on      = true

    when /^cancel$/i, /^off$/i, /^unsubscribe$/i, /^stop$/i, /^die$/i, /^shut up$/
      message = 'You are opted out from Spotify SMS alerts. No more messages will be sent. Text ON to rejoin. Text HELP for help. Msg&Data rates may apply.'
      on      = false

    when /^on$/i
      message = 'Welcome back! Notifications from Spotify are on. Stay tuned for updates about all of our events this week in Austin.'
      on      = true

    when /^help$/i
      message = 'Spotify SMS alerts: Reply STOP or OFF to cancel. Msg frequency depends on user. Msg&Data rates may apply.'

    else
      message = 'Sorry, I don\'t understand that command. Text "help" for list of commands" and "off" to unsubscribe. SMS powered by Twilio!'
      on      = true

    end

    Twilio::SMS.create from: ENV['CALLER_ID'], to: from, body: message

    user.update_attributes! on: on

  end
end

