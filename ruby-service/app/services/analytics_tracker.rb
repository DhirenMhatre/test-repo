require 'json'
require 'digest'

class AnalyticsTracker
  def initialize
    @events = []
    @user_sessions = Hash.new { |h, k| h[k] = [] }
  end

  def track_event(user_id, event_type, data = {})
    event = {
      user_id: user_id,
      event_type: event_type,
      data: data,
      timestamp: Time.now.to_i
    }

    @events << event
    @user_sessions[user_id] << event
  end

  def get_user_events(user_id)
    @user_sessions[user_id]
  end

  def get_all_events
    @events
  end

  def get_events_by_type(event_type)
    @events.select { |e| e[:event_type] == event_type }
  end

  def compute_user_score(user_id)
    events = @user_sessions[user_id]
    return 0 if events.empty?

    total_score = 0
    events.each do |event|
      score = event.dig(:data, :score) || event.dig(:data, 'score')
      total_score += score.to_f if score
    end

    (total_score / events.length).round(2)
  end
end
