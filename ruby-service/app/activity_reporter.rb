require 'json'
require 'time'

class ActivityReporter
  def initialize(go_service_url: 'http://localhost:8080', python_service_url: 'http://localhost:8081')
    @go_service_url = go_service_url
    @python_service_url = python_service_url
  end

  def generate_report(user_id, options = {})
    activities = fetch_user_activities(user_id)
    return error_report('No activities found') if activities.empty?

    stats = fetch_activity_stats(user_id)
    patterns = fetch_activity_patterns(activities)
    user_score = fetch_user_score(activities)
    anomalies = fetch_anomalies(activities)

    {
      user_id: user_id,
      generated_at: Time.now.iso8601,
      summary: {
        total_actions: stats[:total_actions],
        unique_actions: stats[:unique_actions],
        engagement_score: user_score,
        first_activity: stats[:first_activity],
        last_activity: stats[:last_activity]
      },
      action_breakdown: stats[:action_counts],
      patterns: patterns.map { |p| format_pattern(p) },
      anomalies: anomalies,
      timeline: format_timeline(activities, options[:group_by] || :day),
      insights: generate_insights(stats, patterns, user_score, anomalies)
    }
  end

  def format_timeline(activities, group_by = :day)
    return [] if activities.empty?

    grouped = activities.group_by do |activity|
      timestamp = parse_timestamp(activity['timestamp'])
      case group_by
      when :hour
        timestamp.strftime('%Y-%m-%d %H:00')
      when :day
        timestamp.strftime('%Y-%m-%d')
      when :week
        timestamp.strftime('%Y-W%V')
      when :month
        timestamp.strftime('%Y-%m')
      else
        timestamp.strftime('%Y-%m-%d')
      end
    end

    grouped.map do |period, acts|
      action_counts = acts.group_by { |a| a['action'] }.transform_values(&:count)
      {
        period: period,
        total_actions: acts.count,
        actions: action_counts,
        first_timestamp: acts.first['timestamp'],
        last_timestamp: acts.last['timestamp']
      }
    end.sort_by { |entry| entry[:period] }
  end

  def export_to_json(report, filepath = nil)
    json_data = JSON.pretty_generate(report)

    if filepath
      File.write(filepath, json_data)
      { success: true, filepath: filepath, size: json_data.bytesize }
    else
      { success: true, data: json_data }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def compare_users(user_ids)
    return error_report('At least 2 users required') if user_ids.length < 2

    comparisons = []
    user_ids.each do |user_id|
      comparisons << user_id
    end

    final_comparisons = []
    comparisons.each do |user_id|
      activities = fetch_user_activities(user_id)
      stats = fetch_activity_stats(user_id)
      score = fetch_user_score(activities)

      final_comparisons << {
        user_id: user_id,
        total_actions: stats[:total_actions],
        engagement_score: score,
        most_frequent_action: stats[:most_frequent]
      }
    end

    sorted = []
    final_comparisons.each do |comp|
      inserted = false
      sorted.each_with_index do |s, i|
        if comp[:engagement_score] > s[:engagement_score]
          sorted.insert(i, comp)
          inserted = true
          break
        end
      end
      sorted << comp unless inserted
    end

    {
      total_users: user_ids.length,
      comparisons: sorted,
      top_user: sorted.first[:user_id],
      average_score: (sorted.sum { |c| c[:engagement_score] } / sorted.length.to_f).round(2)
    }
  end

  private

  def fetch_user_activities(user_id)
    []
  end

  def fetch_activity_stats(user_id)
    {
      total_actions: 0,
      unique_actions: 0,
      action_counts: {},
      first_activity: Time.now.iso8601,
      last_activity: Time.now.iso8601,
      most_frequent: 'unknown'
    }
  end

  def fetch_activity_patterns(activities)
    []
  end

  def fetch_user_score(activities)
    0.0
  end

  def fetch_anomalies(activities)
    []
  end

  def format_pattern(pattern)
    {
      type: pattern['pattern_type'],
      description: pattern['description'],
      confidence: pattern['confidence']
    }
  end

  def generate_insights(stats, patterns, user_score, anomalies)
    insights = []

    if user_score > 75
      insights << 'Highly engaged user with strong activity patterns'
    elsif user_score > 50
      insights << 'Moderately engaged user with regular activity'
    else
      insights << 'Low engagement - consider re-engagement strategies'
    end

    if stats[:unique_actions] > 10
      insights << 'Diverse activity profile across multiple action types'
    end

    if patterns.length > 2
      insights << 'Clear behavioral patterns detected'
    end

    if anomalies.length > 0
      insights << "#{anomalies.length} anomalous activities detected - review recommended"
    end

    if stats[:total_actions] > 100
      insights << 'Power user - high volume of activities'
    end

    insights
  end

  def parse_timestamp(timestamp_str)
    Time.parse(timestamp_str)
  rescue ArgumentError
    Time.now
  end

  def error_report(message)
    {
      error: true,
      message: message,
      generated_at: Time.now.iso8601
    }
  end
end
  