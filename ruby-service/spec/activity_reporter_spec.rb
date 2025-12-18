require 'spec_helper'
require 'time'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new
  end

  describe '#generate_report' do
    let(:user_id) do
      123
    end

    context 'when activities are present' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T11:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-02T09:00:00Z', 'action' => 'click' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 11,
          action_counts: { 'click' => 100, 'login' => 50 },
          first_activity: '2025-01-01T00:00:00Z',
          last_activity: '2025-01-31T23:59:59Z',
          most_frequent: 'click'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'sequence', 'description' => 'Morning logins', 'confidence' => 0.9 },
          { 'pattern_type' => 'burst', 'description' => 'Rapid clicks', 'confidence' => 0.8 },
          { 'pattern_type' => 'periodic', 'description' => 'Weekly usage', 'confidence' => 0.7 }
        ]
      end

      let(:user_score) do
        80.0
      end

      let(:anomalies) do
        [
          { 'action' => 'delete', 'timestamp' => '2025-01-10T00:00:00Z' },
          { 'action' => 'export', 'timestamp' => '2025-01-15T00:00:00Z' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report with summary, patterns, anomalies, timeline, and insights' do
        report = reporter.generate_report(user_id, group_by: :day)

        expect(report[:user_id]).to eq(user_id)
        expect(report[:generated_at]).to match(/\d{4}-\d{2}-\d{2}T/)

        expect(report[:summary][:total_actions]).to eq(150)
        expect(report[:summary][:unique_actions]).to eq(11)
        expect(report[:summary][:engagement_score]).to eq(80.0)
        expect(report[:summary][:first_activity]).to eq('2025-01-01T00:00:00Z')
        expect(report[:summary][:last_activity]).to eq('2025-01-31T23:59:59Z')

        expect(report[:action_breakdown]).to eq({ 'click' => 100, 'login' => 50 })

        expect(report[:patterns]).to contain_exactly(
          { type: 'sequence', description: 'Morning logins', confidence: 0.9 },
          { type: 'burst', description: 'Rapid clicks', confidence: 0.8 },
          { type: 'periodic', description: 'Weekly usage', confidence: 0.7 }
        )

        expect(report[:anomalies]).to eq(anomalies)

        expect(report[:timeline].map { |e| e[:period] }).to eq(%w[2025-01-01 2025-01-02])
        day1 = report[:timeline].find { |e| e[:period] == '2025-01-01' }
        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(day1[:first_timestamp]).to eq('2025-01-01T10:15:00Z')
        expect(day1[:last_timestamp]).to eq('2025-01-01T11:00:00Z')

        expect(report[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(report[:insights]).to include('Diverse activity profile across multiple action types')
        expect(report[:insights]).to include('Clear behavioral patterns detected')
        expect(report[:insights]).to include('2 anomalous activities detected - review recommended')
        expect(report[:insights]).to include('Power user - high volume of activities')
      end

      it 'respects the group_by option for timeline' do
        report = reporter.generate_report(user_id, group_by: :month)
        expect(report[:timeline].map { |e| e[:period] }).to eq(['2025-01'])
      end
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report' do
        report = reporter.generate_report(user_id)
        expect(report[:error]).to be true
        expect(report[:message]).to eq('No activities found')
        expect(report[:generated_at]).to match(/\d{4}-\d{2}-\d{2}T/)
      end
    end

    context 'with low engagement and no additional signals' do
      let(:activities) do
        [
          { 'timestamp' => '2025-02-01T10:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2025-02-02T12:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2025-02-03T09:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2025-02-04T11:30:00Z', 'action' => 'view' },
          { 'timestamp' => '2025-02-05T08:15:00Z', 'action' => 'view' }
        ]
      end

      let(:stats) do
        {
          total_actions: 5,
          unique_actions: 1,
          action_counts: { 'view' => 5 },
          first_activity: '2025-02-01T10:00:00Z',
          last_activity: '2025-02-05T08:15:00Z',
          most_frequent: 'view'
        }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return([])
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(30.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([])
      end

      it 'includes only low engagement insight' do
        report = reporter.generate_report(user_id)
        expect(report[:insights]).to include('Low engagement - consider re-engagement strategies')
        expect(report[:insights].any? { |s| s.include?('Diverse activity profile') }).to be false
        expect(report[:insights].any? { |s| s.include?('behavioral patterns') }).to be false
        expect(report[:insights].any? { |s| s.include?('anomalous') }).to be false
        expect(report[:insights].any? { |s| s.include?('Power user') }).to be false
      end
    end
  end

  describe '#format_timeline' do
    context 'with empty activities' do
      it 'returns an empty array' do
        result = reporter.format_timeline([], :day)
        expect(result).to eq([])
      end
    end

    context 'grouping by day' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-02T09:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-01T11:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-01T10:15:00Z', 'action' => 'login' }
        ]
      end

      it 'groups and sorts by day with correct counts and timestamps' do
        result = reporter.format_timeline(activities, :day)
        expect(result.map { |e| e[:period] }).to eq(%w[2025-01-01 2025-01-02])

        day1 = result.find { |e| e[:period] == '2025-01-01' }
        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq({ 'click' => 1, 'login' => 1 })
        expect(day1[:first_timestamp]).to eq('2025-01-01T11:00:00Z')
        expect(day1[:last_timestamp]).to eq('2025-01-01T10:15:00Z')

        day2 = result.find { |e| e[:period] == '2025-01-02' }
        expect(day2[:total_actions]).to eq(1)
        expect(day2[:actions]).to eq({ 'click' => 1 })
        expect(day2[:first_timestamp]).to eq('2025-01-02T09:00:00Z')
        expect(day2[:last_timestamp]).to eq('2025-01-02T09:00:00Z')
      end
    end

    context 'grouping by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T11:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-02T09:00:00Z', 'action' => 'click' }
        ]
      end

      it 'groups by hour with proper period strings' do
        result = reporter.format_timeline(activities, :hour)
        expect(result.map { |e| e[:period] }).to eq(['2025-01-01 10:00', '2025-01-01 11:00', '2025-01-02 09:00'])
      end
    end

    context 'grouping by week' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-08T11:00:00Z', 'action' => 'click' }
        ]
      end

      it 'groups by ISO week' do
        result = reporter.format_timeline(activities, :week)
        expected_periods = activities.map { |a| Time.parse(a['timestamp']).strftime('%Y-W%V') }.uniq.sort
        expect(result.map { |e| e[:period] }).to eq(expected_periods)
      end
    end

    context 'grouping by month' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-31T23:59:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-02-01T00:01:00Z', 'action' => 'click' }
        ]
      end

      it 'groups by month' do
        result = reporter.format_timeline(activities, :month)
        expect(result.map { |e| e[:period] }).to eq(%w[2025-01 2025-02])
      end
    end

    context 'with unknown group_by value' do
      let(:activities) do
        [
          { 'timestamp' => '2025-03-10T12:00:00Z', 'action' => 'view' }
        ]
      end

      it 'defaults to day grouping' do
        result = reporter.format_timeline(activities, :unknown)
        expect(result.map { |e| e[:period] }).to eq(['2025-03-10'])
      end
    end

    context 'with invalid timestamp input' do
      let(:activities) do
        [
          { 'timestamp' => 'not-a-time', 'action' => 'view' }
        ]
      end

      it 'falls back to Time.now for grouping while preserving original timestamps' do
        fixed = Time.utc(2022, 12, 31, 12, 34, 56)
        allow(Time).to receive(:now).and_return(fixed)
        result = reporter.format_timeline(activities, :day)
        expect(result.first[:period]).to eq(fixed.strftime('%Y-%m-%d'))
        expect(result.first[:first_timestamp]).to eq('not-a-time')
        expect(result.first[:last_timestamp]).to eq('not-a-time')
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 1,
        summary: { total_actions: 5 },
        timeline: []
      }
    end

    context 'when filepath is not provided' do
      it 'returns success with JSON data' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be true
        expect(result[:data]).to be_a(String)
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq(1)
        expect(parsed['summary']['total_actions']).to eq(5)
      end
    end

    context 'when filepath is provided' do
      let(:filepath) do
        '/tmp/activity_report.json'
      end

      it 'writes the file and returns metadata including size' do
        allow(File).to receive(:write).and_return(100)
        expected_size = JSON.pretty_generate(report).bytesize
        result = reporter.export_to_json(report, filepath)
        expect(File).to have_received(:write).with(filepath, kind_of(String))
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(filepath)
        expect(result[:size]).to eq(expected_size)
      end
    end

    context 'when an error occurs during export' do
      it 'captures and returns the error' do
        allow(JSON).to receive(:pretty_generate).and_raise(StandardError.new('boom'))
        result = reporter.export_to_json(report)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('boom')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users([1])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to match(/\d{4}-\d{2}-\d{2}T/)
      end
    end

    context 'with multiple users' do
      let(:user_ids) do
        [1, 2, 3]
      end

      let(:scores) do
        { 1 => 60.5, 2 => 82.3, 3 => 10.0 }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities) do |_uid|
          [
            { 'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'a' }
          ]
        end

        allow(reporter).to receive(:fetch_activity_stats) do |uid|
          {
            total_actions: { 1 => 10, 2 => 20, 3 => 5 }[uid],
            unique_actions: 2,
            action_counts: { 'a' => 1 },
            first_activity: '2025-01-01T00:00:00Z',
            last_activity: '2025-01-31T00:00:00Z',
            most_frequent: 'a'
          }
        end

        allow(reporter).to receive(:fetch_user_score) do |_activities|
          # In this stub we cannot see uid, so use separate stub on per-user call below
          0.0
        end

        # Override per-user score based on user_id by stubbing with arguments in sequence
        allow(reporter).to receive(:fetch_user_score) do |_acts|
          # This method is called with activities array; emulate mapping by count pattern if needed
          # Instead, return a distinct value each time using a queue:
          @score_calls ||= 0
          @score_calls += 1
          case @score_calls
          when 1
            scores[1]
          when 2
            scores[2]
          else
            scores[3]
          end
        end
      end

      it 'returns sorted comparisons, top user, and correct average score' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        comps = result[:comparisons]
        expect(comps.map { |c| c[:user_id] }).to eq([2, 1, 3])
        expect(comps.first[:engagement_score]).to eq(82.3)
        expect(comps.first[:most_frequent_action]).to eq('a')
        expect(result[:top_user]).to eq(2)
        expect(result[:average_score]).to eq(((60.5 + 82.3 + 10.0) / 3.0).round(2))
      end
    end
  end
end
