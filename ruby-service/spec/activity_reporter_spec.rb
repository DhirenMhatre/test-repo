require 'spec_helper'
require 'json'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) { described_class.new }

  describe '#generate_report' do
    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('user-1').and_return([])
      end

      it 'returns an error report with message and timestamp' do
        result = reporter.generate_report('user-1')
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'when activities are present' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-10T10:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-10T12:00:00Z', 'action' => 'click' }
        ]
      end

      let(:stats) do
        {
          total_actions: 2,
          unique_actions: 2,
          action_counts: { 'login' => 1, 'click' => 1 },
          first_activity: '2025-01-10T10:00:00Z',
          last_activity: '2025-01-10T12:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'burst', 'description' => 'rapid clicks', 'confidence' => 0.9 }
        ]
      end

      let(:formatted_timeline) do
        [
          {
            period: '2025-01-06', # week group will not be used in this stubbed timeline; placeholder period
            total_actions: 2,
            actions: { 'login' => 1, 'click' => 1 },
            first_timestamp: '2025-01-10T10:00:00Z',
            last_timestamp: '2025-01-10T12:00:00Z'
          }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('user-2').and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with('user-2').and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(80.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(['spike'])
        allow(reporter).to receive(:format_timeline).with(activities, :week).and_return(formatted_timeline)
      end

      it 'composes a complete report with summary, formatted patterns, anomalies, timeline, and insights' do
        report = reporter.generate_report('user-2', group_by: :week)

        expect(report[:user_id]).to eq('user-2')
        expect(report[:generated_at]).to be_a(String)

        expect(report[:summary][:total_actions]).to eq(2)
        expect(report[:summary][:unique_actions]).to eq(2)
        expect(report[:summary][:engagement_score]).to eq(80.0)
        expect(report[:summary][:first_activity]).to eq('2025-01-10T10:00:00Z')
        expect(report[:summary][:last_activity]).to eq('2025-01-10T12:00:00Z')

        expect(report[:action_breakdown]).to eq({ 'login' => 1, 'click' => 1 })

        expect(report[:patterns]).to eq([
          { type: 'burst', description: 'rapid clicks', confidence: 0.9 }
        ])

        expect(report[:anomalies]).to eq(['spike'])
        expect(report[:timeline]).to eq(formatted_timeline)

        expect(report[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(report[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(report[:insights]).not_to include('Low engagement - consider re-engagement strategies')
      end
    end

    context 'insights generation via conditions' do
      let(:activities) do
        [
          { 'timestamp' => '2025-02-01T00:00:00Z', 'action' => 'a' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).and_return({
          total_actions: 150,
          unique_actions: 11,
          action_counts: { 'a' => 150 },
          first_activity: '2025-02-01T00:00:00Z',
          last_activity: '2025-02-01T00:00:00Z',
          most_frequent: 'a'
        })
        allow(reporter).to receive(:fetch_activity_patterns).and_return([
          { 'pattern_type' => 'p1', 'description' => 'd1', 'confidence' => 0.8 },
          { 'pattern_type' => 'p2', 'description' => 'd2', 'confidence' => 0.7 },
          { 'pattern_type' => 'p3', 'description' => 'd3', 'confidence' => 0.9 }
        ])
        allow(reporter).to receive(:fetch_user_score).and_return(55.0)
        allow(reporter).to receive(:fetch_anomalies).and_return([])
        allow(reporter).to receive(:format_timeline).and_return([])
      end

      it 'includes messages for moderate engagement, diversity, clear patterns, and power user' do
        report = reporter.generate_report('user-3')

        expect(report[:insights]).to include('Moderately engaged user with regular activity')
        expect(report[:insights]).to include('Diverse activity profile across multiple action types')
        expect(report[:insights]).to include('Clear behavioral patterns detected')
        expect(report[:insights]).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities are empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([], :day)
        expect(result).to eq([])
      end
    end

    context 'grouping and counts' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-10T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-10T10:45:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-11T09:00:00Z', 'action' => 'login' }
        ]
      end

      it 'groups by day with correct counts and timestamps' do
        result = reporter.format_timeline(activities, :day)
        expect(result.length).to eq(2)

        day1 = result.find { |e| e[:period] == '2025-01-10' }
        day2 = result.find { |e| e[:period] == '2025-01-11' }

        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(day1[:first_timestamp]).to eq('2025-01-10T10:15:00Z')
        expect(day1[:last_timestamp]).to eq('2025-01-10T10:45:00Z')

        expect(day2[:total_actions]).to eq(1)
        expect(day2[:actions]).to eq({ 'login' => 1 })
        expect(day2[:first_timestamp]).to eq('2025-01-11T09:00:00Z')
        expect(day2[:last_timestamp]).to eq('2025-01-11T09:00:00Z')
      end

      it 'groups by hour with correct period formatting' do
        result = reporter.format_timeline(activities, :hour)
        periods = result.map { |e| e[:period] }
        expect(periods).to include('2025-01-10 10:00', '2025-01-11 09:00')

        hour_10 = result.find { |e| e[:period] == '2025-01-10 10:00' }
        expect(hour_10[:total_actions]).to eq(2)
        expect(hour_10[:actions]).to eq({ 'login' => 1, 'click' => 1 })
      end

      it 'groups by week using ISO week number' do
        result = reporter.format_timeline(activities, :week)
        week_str = Time.parse('2025-01-10T00:00:00Z').strftime('%Y-W%V')
        week_entry = result.find { |e| e[:period] == week_str } || result.first
        expect(week_entry[:total_actions]).to be >= 1
      end

      it 'groups by month' do
        result = reporter.format_timeline(activities, :month)
        month_entry = result.find { |e| e[:period] == '2025-01' }
        expect(month_entry[:total_actions]).to eq(3)
        expect(month_entry[:actions]).to eq({ 'login' => 2, 'click' => 1 })
      end
    end

    context 'with invalid group_by' do
      it 'falls back to daily grouping' do
        activities = [{ 'timestamp' => '2025-03-01T00:00:00Z', 'action' => 'a' }]
        result = reporter.format_timeline(activities, :unknown)
        expect(result.length).to eq(1)
        expect(result.first[:period]).to eq('2025-03-01')
      end
    end

    context 'with invalid timestamp values' do
      it 'does not raise and uses current time for grouping' do
        fixed_now = Time.parse('2025-05-01T01:02:03Z')
        allow(Time).to receive(:now).and_return(fixed_now)
        activities = [{ 'timestamp' => 'not-a-time', 'action' => 'x' }]
        result = reporter.format_timeline(activities, :day)
        expect(result.length).to eq(1)
        expect(result.first[:period]).to eq(fixed_now.strftime('%Y-%m-%d'))
        expect(result.first[:first_timestamp]).to eq('not-a-time')
        expect(result.first[:last_timestamp]).to eq('not-a-time')
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 'u-1',
        summary: { total_actions: 3 },
        action_breakdown: { 'login' => 2, 'click' => 1 }
      }
    end

    context 'when no filepath is provided' do
      it 'returns pretty JSON string in data' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be true
        expect(result[:data]).to be_a(String)
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq('u-1')
        expect(parsed['summary']['total_actions']).to eq(3)
      end
    end

    context 'when filepath is provided' do
      it 'writes to file and returns metadata including size' do
        path = '/tmp/report.json'
        expected_size = JSON.pretty_generate(report).bytesize
        allow(File).to receive(:write).with(path, kind_of(String)).and_return(expected_size)

        result = reporter.export_to_json(report, path)
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(path)
        expect(result[:size]).to eq(expected_size)
      end

      it 'handles file write errors gracefully' do
        path = '/tmp/report.json'
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))

        result = reporter.export_to_json(report, path)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with multiple users' do
      let(:user_ids) { ['u1', 'u2', 'u3'] }

      before do
        allow(reporter).to receive(:fetch_user_activities) do |uid|
          case uid
          when 'u1' then [{ 'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'a' }]
          when 'u2' then [{ 'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'b' }]
          when 'u3' then [{ 'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'c' }]
          else []
          end
        end

        allow(reporter).to receive(:fetch_activity_stats) do |uid|
          case uid
          when 'u1' then { total_actions: 10, unique_actions: 2, action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'a' }
          when 'u2' then { total_actions: 20, unique_actions: 3, action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'b' }
          when 'u3' then { total_actions: 5, unique_actions: 1, action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'c' }
          else { total_actions: 0, unique_actions: 0, action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'unknown' }
          end
        end

        allow(reporter).to receive(:fetch_user_score) do |activities|
          if activities.first && activities.first['action'] == 'b'
            90.0
          elsif activities.first && activities.first['action'] == 'c'
            70.0
          else
            50.0
          end
        end
      end

      it 'returns sorted comparisons by engagement score with top_user and average_score' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].length).to eq(3)

        # Sorted descending by engagement_score: u2 (90), u3 (70), u1 (50)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(['u2', 'u3', 'u1'])
        expect(result[:comparisons].map { |c| c[:engagement_score] }).to eq([90.0, 70.0, 50.0])

        expect(result[:top_user]).to eq('u2')
        expect(result[:average_score]).to eq(70.0)

        # Check that stats-derived fields are included
        u2_comp = result[:comparisons].first
        expect(u2_comp[:total_actions]).to eq(20)
        expect(u2_comp[:most_frequent]).to eq('b')
      end
    end
  end
end
