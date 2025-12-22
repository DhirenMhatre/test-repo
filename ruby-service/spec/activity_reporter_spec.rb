require 'spec_helper'
require 'json'
require 'time'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new(
      go_service_url: 'http://go.example',
      python_service_url: 'http://py.example'
    )
  end

  describe '#initialize' do
    it 'creates an instance with custom service URLs without error' do
      instance = described_class.new(go_service_url: 'http://go', python_service_url: 'http://py')
      expect(instance).to be_a(described_class)
    end
  end

  describe '#generate_report' do
    let(:user_id) { 'user-123' }

    context 'when no activities are found' do
      it 'returns an error report' do
        fixed_time = Time.parse('2025-01-01T00:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_time)
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])

        result = reporter.generate_report(user_id)

        expect(result[:error]).to be(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'when activities exist' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T10:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T11:00:00Z', 'action' => 'click' }
        ]
      end

      let(:stats) do
        {
          total_actions: 2,
          unique_actions: 2,
          action_counts: { 'login' => 1, 'click' => 1 },
          first_activity: '2025-01-01T10:00:00Z',
          last_activity: '2025-01-01T11:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'burst', 'description' => 'morning activity', 'confidence' => 0.9 },
          { 'pattern_type' => 'regular', 'description' => 'weekly check', 'confidence' => 0.7 }
        ]
      end

      let(:formatted_patterns) do
        [
          { type: 'burst', description: 'morning activity', confidence: 0.9 },
          { type: 'regular', description: 'weekly check', confidence: 0.7 }
        ]
      end

      let(:timeline_stub) do
        [
          {
            period: '2025-01-01',
            total_actions: 2,
            actions: { 'login' => 1, 'click' => 1 },
            first_timestamp: '2025-01-01T10:00:00Z',
            last_timestamp: '2025-01-01T11:00:00Z'
          }
        ]
      end

      it 'builds a comprehensive report with summary, patterns, anomalies, timeline, and insights' do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(80.5)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(['spike'])
        allow(reporter).to receive(:format_timeline).and_return(timeline_stub)

        result = reporter.generate_report(user_id)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:summary][:total_actions]).to eq(2)
        expect(result[:summary][:unique_actions]).to eq(2)
        expect(result[:summary][:engagement_score]).to eq(80.5)
        expect(result[:summary][:first_activity]).to eq('2025-01-01T10:00:00Z')
        expect(result[:summary][:last_activity]).to eq('2025-01-01T11:00:00Z')
        expect(result[:action_breakdown]).to eq({ 'login' => 1, 'click' => 1 })
        expect(result[:patterns]).to eq(formatted_patterns)
        expect(result[:anomalies]).to eq(['spike'])
        expect(result[:timeline]).to eq(timeline_stub)
        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(result[:insights]).not_to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).not_to include('Clear behavioral patterns detected')
        expect(result[:insights]).not_to include('Power user - high volume of activities')
      end

      it 'respects the group_by option when building the timeline' do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return([])
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(55.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([])
        expect(reporter).to receive(:format_timeline).with(activities, :hour).and_return(timeline_stub)

        reporter.generate_report(user_id, group_by: :hour)
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities are empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'with group_by :day' do
      it 'groups activities by day and sorts periods' do
        activities = [
          { 'timestamp' => '2025-01-02T09:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-01T10:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T12:00:00Z', 'action' => 'view' }
        ]

        timeline = reporter.format_timeline(activities, :day)

        expect(timeline.map { |e| e[:period] }).to eq(%w[2025-01-01 2025-01-02])
        day1 = timeline[0]
        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq({ 'login' => 1, 'view' => 1 })
        expect(day1[:first_timestamp]).to eq('2025-01-01T10:00:00Z')
        expect(day1[:last_timestamp]).to eq('2025-01-01T12:00:00Z')
      end
    end

    context 'with group_by :hour' do
      it 'groups activities by hour' do
        activities = [
          { 'timestamp' => '2025-01-01T10:05:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T10:45:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-01T11:00:00Z', 'action' => 'view' }
        ]

        timeline = reporter.format_timeline(activities, :hour)

        expect(timeline.map { |e| e[:period] }).to eq(['2025-01-01 10:00', '2025-01-01 11:00'])
        hour10 = timeline[0]
        expect(hour10[:total_actions]).to eq(2)
        expect(hour10[:actions]).to eq({ 'login' => 1, 'click' => 1 })
      end
    end

    context 'with invalid group_by value' do
      it 'defaults to day grouping' do
        activities = [
          { 'timestamp' => '2025-01-01T10:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T12:00:00Z', 'action' => 'view' }
        ]

        timeline = reporter.format_timeline(activities, :year)

        expect(timeline.length).to eq(1)
        expect(timeline.first[:period]).to eq('2025-01-01')
      end
    end

    context 'when timestamps are invalid strings' do
      it 'falls back to Time.now without raising and preserves original first/last timestamps' do
        fixed_time = Time.parse('2025-02-01T00:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_time)
        activities = [
          { 'timestamp' => 'not-a-time', 'action' => 'login' }
        ]

        timeline = reporter.format_timeline(activities, :day)

        expect(timeline.length).to eq(1)
        expect(timeline.first[:period]).to eq('2025-02-01')
        expect(timeline.first[:first_timestamp]).to eq('not-a-time')
        expect(timeline.first[:last_timestamp]).to eq('not-a-time')
      end
    end

    context 'preserves the order of activities within a period for first/last timestamps' do
      it 'uses the first and last occurrence order from the original list' do
        activities = [
          { 'timestamp' => '2025-01-01T11:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-01T10:00:00Z', 'action' => 'login' }
        ]

        timeline = reporter.format_timeline(activities, :day)

        expect(timeline.length).to eq(1)
        expect(timeline.first[:first_timestamp]).to eq('2025-01-01T11:00:00Z')
        expect(timeline.first[:last_timestamp]).to eq('2025-01-01T10:00:00Z')
      end
    end
  end

  describe '#export_to_json' do
    let(:report_hash) do
      {
        user_id: 'u',
        generated_at: '2025-01-01T00:00:00Z',
        summary: { total_actions: 1, unique_actions: 1, engagement_score: 10.0, first_activity: 't1',
                   last_activity: 't1' },
        action_breakdown: { 'login' => 1 },
        patterns: [],
        anomalies: [],
        timeline: [],
        insights: []
      }
    end

    context 'when no filepath is provided' do
      it 'returns a success response with JSON data' do
        result = reporter.export_to_json(report_hash)
        expect(result[:success]).to be(true)
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq('u')
      end
    end

    context 'when a filepath is provided' do
      it 'writes the file and returns metadata' do
        path = '/tmp/fake_report.json'
        expected_size = JSON.pretty_generate(report_hash).bytesize
        allow(File).to receive(:write).and_return(expected_size)

        result = reporter.export_to_json(report_hash, path)

        expect(File).to have_received(:write).with(path, kind_of(String))
        expect(result[:success]).to be(true)
        expect(result[:filepath]).to eq(path)
        expect(result[:size]).to eq(expected_size)
      end
    end

    context 'when writing fails' do
      it 'returns an error response' do
        path = '/tmp/unwritable.json'
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))

        result = reporter.export_to_json(report_hash, path)

        expect(result[:success]).to be(false)
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than 2 users are provided' do
      it 'returns an error report' do
        fixed_time = Time.parse('2025-01-01T00:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_time)

        result = reporter.compare_users(['only-one'])

        expect(result[:error]).to be(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with multiple users' do
      it 'returns sorted comparisons, top user, and average score' do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{ 'timestamp' => 't',
                                                                                    'action' => 'a' }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{ 'timestamp' => 't',
                                                                                    'action' => 'a' }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([{ 'timestamp' => 't',
                                                                                    'action' => 'a' }])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 3, unique_actions: 2,
                                                                                  action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'click' })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 5, unique_actions: 3,
                                                                                  action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'view' })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 1, unique_actions: 1,
                                                                                  action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'login' })

        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => 't', 'action' => 'a' }]).and_return(60.1,
                                                                                                                 70.0, 10.0)

        result = reporter.compare_users(%w[u1 u2 u3])

        expect(result[:total_users]).to eq(3)
        expect(result[:top_user]).to eq('u2')
        expect(result[:average_score]).to eq(46.7)

        comparisons = result[:comparisons]
        expect(comparisons.map { |c| c[:user_id] }).to eq(%w[u2 u1 u3])
        expect(comparisons[0]).to include(user_id: 'u2', total_actions: 5, engagement_score: 70.0,
                                          most_frequent_action: 'view')
        expect(comparisons[1]).to include(user_id: 'u1', total_actions: 3, engagement_score: 60.1,
                                          most_frequent_action: 'click')
        expect(comparisons[2]).to include(user_id: 'u3', total_actions: 1, engagement_score: 10.0,
                                          most_frequent_action: 'login')
      end
    end

    context 'when multiple users have equal scores' do
      it 'preserves input order among equal scores' do
        %w[a b c].each do |u|
          allow(reporter).to receive(:fetch_user_activities).with(u).and_return([{ 'timestamp' => 't',
                                                                                   'action' => 'a' }])
          allow(reporter).to receive(:fetch_activity_stats).with(u).and_return({ total_actions: 1, unique_actions: 1,
                                                                                 action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'x' })
        end
        allow(reporter).to receive(:fetch_user_score).and_return(50.0)

        result = reporter.compare_users(%w[a b c])

        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[a b c])
      end
    end
  end
end
