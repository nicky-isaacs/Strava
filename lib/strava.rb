require 'strava/api/v3'

module GNIPStrava

  MAY_FIRST_2014 = Time.parse '2014-05-01T00:00:00Z'
  @@_gnip_cycling_club
  @@_gnip_running_club

  # Club accessors
  def self.non_gnip_strava_clubs
    perform_request_with_timeout{ |client| client.retrieve_current_athlete['clubs'].select{ |club| !['gnip', 'gnip running'].include?(club['name'].downcase)  } }
  end

  def self.gnip_cycling_club
    @@_gnip_cycling_club ||=  perform_request_with_timeout{ |client| client.retrieve_current_athlete['clubs'].detect{ |club| club['name'].downcase == 'gnip' } }
    @@_gnip_cycling_club || {}
  end


  def self.gnip_running_club
    @@_gnip_running_club ||= perform_request_with_timeout{ |client| client.retrieve_current_athlete['clubs'].detect{ |club| club['name'].downcase == 'gnip running' } }
    @@_gnip_running_club || {}
  end

  def self.all_clubs_for_athlete
    perform_request_with_timeout{ |client| client.retrieve_current_athlete['clubs'] }
  end

  # Activity methods

  def self.non_gnip_strava_meters_in_may_2014
    non_gnip_strava_clubs.map do |club|
      return unless club # Ignore nil clubs
      may_segments = filter_may_2014_segments strava_segments_for_club_id( club['id'] )
      meters = may_segments.inject(0) { |accumulator, segment| accumulator + segment['distance'] }
      {
          club['name'] => meters
      }
    end
  end

  def self.get_club_activities(club_id, page=1, per_page)
    args={
        page: page,
        per_page: per_page
    }
    GNIPStrava.client.list_club_activities club_id, args
  end

  def self.all_gnip_activities
    cycling = perform_request_with_timeout{ |client| client.list_club_activities gnip_cycling_club['id'] }
    running = perform_request_with_timeout{ |client| client.list_club_activities gnip_running_club['id'] }
    cycling + running
  end

  def self.all_gnip_activities_in_may_2014
    [gnip_cycling_club['id'], gnip_running_club['id']].inject([]){ |acc, id| acc + activities_for_club_for_may_2014(id) }.sort_by { |activity| Time.parse activity['start_date'] }
  end

  def self.activities_for_club_for_may_2014(club_id)
    activities=[]
    page_size = 200

    page_index=1
    begin
      page = get_club_activities(club_id, page_index, page_size).sort_by { |activity| Time.parse activity['start_date'] }
      activities = activities + page
      page_index += 1
    end while Time.parse(activities.first['start_date']) > MAY_FIRST_2014 && !page.empty? # Smallest should be first in the list, and oldest

    activities.select{ |activity| Time.parse( activity['start_date'] ) > MAY_FIRST_2014 }.sort_by { |activity| Time.parse activity['start_date'] }
  end

  # Configuration stuff

  private

  def self.strava_configurations_file
    File.join File.dirname(__FILE__), '..', 'config', 'strava.yml'
  end

  def self.load_configurations
    YAML.load_file strava_configurations_file
  end

  def self.client
    c = load_configurations
    @client ||= Strava::Api::V3::Client.new( access_token: c['access_token'], client_secret: c['client_secret'])
    @client
  end

  def self.perform_request_with_timeout(&block)
    begin
      block.call client
    rescue Strava::Api::V3::ClientError => e
      if e.response_body['message'].downcase.include? 'rate limit exceeded'
        sleep 10
        retry
      end
    end
  end

  def self.method_missing(method, *args, &block)
    if client.respond_to? method
      client.send method, *args, &block
    else
      super
    end
  end

end
