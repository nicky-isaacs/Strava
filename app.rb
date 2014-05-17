require 'sinatra'
require './lib/strava'

@@_activity_cache={};
CACHE_TIME = 20*60

get '/' do
  redirect to '/strava'
end

get '/strava' do
  clubs = create_strava_report
  erb :strava, locals: {clubs: clubs}
end

def create_strava_report
  return cached_result if cache_is_valid?

  clubs = GNIPStrava.all_clubs_for_athlete
  club_activities=[]

  threads=[]

  for club in clubs do
    threads << Thread.new do
      may_activities = format_activites GNIPStrava.activities_for_club_for_may_2014(club['id'])
      begin
        club = club['name']
        club_activities << { name: club, activities: may_activities }
      rescue
        club_activities << { name: 'Error', activities: [] }
      end
    end
  end
  threads.each{ |t| t.join }

  cache_result club_activities
  club_activities
end

def format_activites(activities)
  activities.map{ |a| format_activity a }
end

def format_activity(activity)
  name = activity['athlete']['firstname'] + ' ' + activity['athlete']['lastname']
  location = "#{activity['location_city']}, #{activity['location_country']}"
  {
    name: name,
    location: location,
    start_date: activity['start_date'],
    type: activity['type'],
    distance: activity['distance'],
    elevation: activity['total_elevation_gain']
  }
end

def cache_result(result)
  @@_activity_cache={
    time: Time.now,
    payload: result
  }
end

def cached_result
  @@_activity_cache[:payload]
end

def cache_is_valid?
  return false unless @@_activity_cache[:time]
  diff = Time.now - @@_activity_cache[:time]
  diff < CACHE_TIME && cached_result
end
