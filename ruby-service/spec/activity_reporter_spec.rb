require 'spec_helper'
require 'time'
require 'rails_helper'

RSpec.describe ActivityReporter do
  let(:fixed_time) { Time.parse('2025-01-16T12:00:00Z') }

  describe '#initialize' do
    context 'with default URLs' do
      let(:reporter) { described_class.new }

      it 'creates an instance' do
        expect(reporter).to be_a(described_class)
      end
    end

    context 'with custom URLs' do
      let(:reporter) { described_class.new(go_service_url: 'http://go', python_service_url: 'http://py') }

      it 'creates an instance without error' do
        expect(reporter).to be_a(described_class)
      end
    end
  end

  describe '#generate_report' do
    let(:reporter) { described_class.new }

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
    end

    context 'when no activities exist' do
      before do
        expect(reporter).to receive(:fetch_user_activities).with('user0').and_return([])
        expect(reporter).not_to receive(:fetch_activity_stats)
        expect(reporter).not_to receive(:fetch_activity_patterns)
        expect(reporter).not_to receive(:fetch_user_score)
        expect(reporter).not_to receive(:fetch_anomalies)
      end

      it 'returns an error report with message and timestamp' do
        result = reporter.generate_report('user0')
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with activities present' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-14T08:00:00Z' },
          { 'action' => 'click', 'timestamp' => '2025-01-14T09:00:00Z' },
          { 'action' => 'logout', 'timestamp' => '2025-01-15T10:00:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 3,
          action_counts: { 'login' => 30, 'click' => 100, 'logout' => 20 },
          first_activity: '2025-01-14T08:00:00Z',
          last_activity: '2025-01-15T10:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'burst', 'description' => 'morning activity', 'confidence' => 0.9 },
          { 'pattern_type' => 'sequence', 'description' => 'login then click', 'confidence' => 0.85 },
          { 'pattern_type' => 'periodic', 'description' => 'daily check-in', 'confidence' => 0.8 }
        ]
      end

      let(:user_score) { 80.5 }
      let(:anomalies) { [{ 'action' => 'click', 'timestamp' => '2025-01-15T00:00:00Z' }] }

      before do
        expect(reporter).to receive(:fetch_user_activities).with('user123').and_return(activities)
        expect(reporter).to receive(:fetch_activity_stats).with('user123').and_return(stats)
        expect(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        expect(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        expect(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'returns a comprehensive report with summary, patterns, anomalies, timeline, and insights' do
        report = reporter.generate_report('user123', group_by: :day)

        expect(report[:user_id]).to eq('user123')
        expect(report[:generated_at]).to eq(fixed_time.iso8601)

        expect(report[:summary][:total_actions]).to eq(150)
        expect(report[:summary][:unique_actions]).to eq(3)
        expect(report[:summary][:engagement_score]).to eq(user_score)
        expect(report[:summary][:first_activity]).to eq('2025-01-14T08:00:00Z')
        expect(report[:summary][:last_activity]).to eq('2025-01-15T10:00:00Z')

        expect(report[:action_breakdown]).to eq(stats[:action_counts])

        expect(report[:patterns]).to eq([
                                          { type: 'burst', description: 'morning activity', confidence: 0.9 },
                                          { type: 'sequence', description: 'login then click', confidence: 0.85 },
                                          { type: 'periodic', description: 'daily check-in', confidence: 0.8 }
                                        ])

        expect(report[:anomalies]).to eq(anomalies)

        expect(report[:timeline].size).to eq(2)
        expect(report[:timeline][0][:period]).to eq('2025-01-14')
        expect(report[:timeline][0][:total_actions]).to eq(2)
        expect(report[:timeline][0][:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(report[:timeline][0][:first_timestamp]).to eq('2025-01-14T08:00:00Z')
        expect(report[:timeline][0][:last_timestamp]).to eq('2025-01-14T09:00:00Z')

        expect(report[:timeline][1][:period]).to eq('2025-01-15')
        expect(report[:timeline][1][:total_actions]).to eq(1)
        expect(report[:timeline][1][:actions]).to eq({ 'logout' => 1 })
        expect(report[:timeline][1][:first_timestamp]).to eq('2025-01-15T10:00:00Z')
        expect(report[:timeline][1][:last_timestamp]).to eq('2025-01-15T10:00:00Z')

        expect(report[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(report[:insights]).to include('Clear behavioral patterns detected')
        expect(report[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(report[:insights]).to include('Power user - high volume of activities')
      end
    end

    context 'insight thresholds' do
      let(:reporter) { described_class.new }
      let(:activities) { [{ 'action' => 'a', 'timestamp' => '2025-01-01T00:00:00Z' }] }

      before do
        allow(reporter).to receive(:fetch_user_activities).and_return(activities)
        allow(reporter).to receive(:fetch_activity_patterns).and_return([])
        allow(reporter).to receive(:fetch_anomalies).and_return([])
        allow(reporter).to receive(:fetch_activity_stats).and_return({
                                                                       total_actions: 1,
                                                                       unique_actions: 11,
                                                                       action_counts: { 'a' => 1 },
                                                                       first_activity: '2025-01-01T00:00:00Z',
                                                                       last_activity: '2025-01-01T00:00:00Z',
                                                                       most_frequent: 'a'
                                                                     })
        allow(Time).to receive(:now).and_return(fixed_time)
      end

      it 'includes moderate engagement insight for score in (50,75]' do
        allow(reporter).to receive(:fetch_user_score).and_return(65.0)
        report = reporter.generate_report('u1')
        expect(report[:insights]).to include('Moderately engaged user with regular activity')
        expect(report[:insights]).to include('Diverse activity profile across multiple action types')
      end

      it 'includes low engagement insight for score <= 50' do
        allow(reporter).to receive(:fetch_user_score).and_return(40.0)
        report = reporter.generate_report('u2')
        expect(report[:insights]).to include('Low engagement - consider re-engagement strategies')
        expect(report[:insights]).to include('Diverse activity profile across multiple action types')
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) { described_class.new }

    context 'with empty activities' do
      it 'returns an empty array' do
        result = reporter.format_timeline([])
        expect(result).to eq([])
      end
    end

    context 'grouping by hour' do
      let(:activities) do
        [
          { 'action' => 'click', 'timestamp' => '2025-01-14T08:30:00Z' },
          { 'action' => 'login', 'timestamp' => '2025-01-14T08:45:00Z' },
          { 'action' => 'logout', 'timestamp' => '2025-01-14T09:00:00Z' }
        ]
      end

      it 'groups actions correctly by hour and sorts periods' do
        timeline = reporter.format_timeline(activities, :hour)
        expect(timeline.length).to eq(2)
        expect(timeline[0][:period]).to eq('2025-01-14 08:00')
        expect(timeline[0][:total_actions]).to eq(2)
        expect(timeline[0][:actions]).to eq({ 'click' => 1, 'login' => 1 })
        expect(timeline[1][:period]).to eq('2025-01-14 09:00')
        expect(timeline[1][:total_actions]).to eq(1)
        expect(timeline[1][:actions]).to eq({ 'logout' => 1 })
      end
    end

    context 'grouping by day' do
      let(:activities) do
        [
          { 'action' => 'a', 'timestamp' => '2025-02-01T10:00:00Z' },
          { 'action' => 'b', 'timestamp' => '2025-02-01T12:00:00Z' },
          { 'action' => 'c', 'timestamp' => '2025-02-02T09:00:00Z' }
        ]
      end

      it 'groups actions by day' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.map { |t| t[:period] }).to eq(%w[2025-02-01 2025-02-02])
        expect(timeline[0][:actions]).to eq({ 'a' => 1, 'b' => 1 })
        expect(timeline[1][:actions]).to eq({ 'c' => 1 })
      end
    end

    context 'grouping by week' do
      let(:activities) do
        [
          { 'action' => 'a', 'timestamp' => '2025-01-01T10:00:00Z' },
          { 'action' => 'b', 'timestamp' => '2025-01-07T12:00:00Z' }
        ]
      end

      it 'groups actions by ISO week' do
        timeline = reporter.format_timeline(activities, :week)
        expect(timeline.map { |t| t[:period] }).to all(match(/\A\d{4}-W\d{2}\z/))
        expect(timeline.length).to be >= 1
      end
    end

    context 'grouping by month' do
      let(:activities) do
        [
          { 'action' => 'a', 'timestamp' => '2025-03-01T10:00:00Z' },
          { 'action' => 'b', 'timestamp' => '2025-03-15T12:00:00Z' },
          { 'action' => 'c', 'timestamp' => '2025-04-01T09:00:00Z' }
        ]
      end

      it 'groups actions by month' do
        timeline = reporter.format_timeline(activities, :month)
        expect(timeline.map { |t| t[:period] }).to eq(%w[2025-03 2025-04])
        expect(timeline[0][:total_actions]).to eq(2)
        expect(timeline[1][:total_actions]).to eq(1)
      end
    end

    context 'with invalid timestamp values' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => 'not-a-time' }
        ]
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_time)
      end

      it 'falls back to Time.now for grouping and preserves original timestamps' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.length).to eq(1)
        expect(timeline[0][:period]).to eq(fixed_time.strftime('%Y-%m-%d'))
        expect(timeline[0][:first_timestamp]).to eq('not-a-time')
        expect(timeline[0][:last_timestamp]).to eq('not-a-time')
      end
    end

    context 'with unknown group_by value' do
      let(:activities) do
        [
          { 'action' => 'a', 'timestamp' => '2025-05-01T10:00:00Z' },
          { 'action' => 'b', 'timestamp' => '2025-05-02T10:00:00Z' }
        ]
      end

      it 'defaults to day grouping' do
        timeline = reporter.format_timeline(activities, :unknown)
        expect(timeline.map { |t| t[:period] }).to eq(%w[2025-05-01 2025-05-02])
      end
    end
  end

  describe '#export_to_json' do
    let(:reporter) { described_class.new }
    let(:data) do
      {
        user_id: 'u1',
        summary: {
          total_actions: 3
        }
      }
    end

    context 'when no filepath is provided' do
      it 'returns pretty JSON data in the response' do
        result = reporter.export_to_json(data)
        expect(result[:success]).to be true
        expect(result[:data]).to be_a(String)
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq('u1')
        expect(parsed['summary']['total_actions']).to eq(3)
      end
    end

    context 'when a filepath is provided' do
      it 'writes to the file and returns filepath and size' do
        dir = Dir.mktmpdir
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(data, path)
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(path)
        expected_json = JSON.pretty_generate(data)
        expect(result[:size]).to eq(expected_json.bytesize)
        written = File.read(path)
        expect(written).to eq(expected_json)
      end
    end

    context 'when writing fails' do
      it 'returns an error response' do
        allow(File).to receive(:write).and_raise(StandardError.new('boom'))
        result = reporter.export_to_json(data, '/tmp/somewhere.json')
        expect(result[:success]).to be false
        expect(result[:error]).to eq('boom')
      end
    end
  end

  describe '#compare_users' do
    let(:reporter) { described_class.new }

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
    end

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only_one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with two users' do
      it 'compares users, sorts by engagement score, and computes average' do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{ 'action' => 'a',
                                                                                    'timestamp' => '2025-01-01T00:00:00Z' }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{ 'action' => 'b',
                                                                                    'timestamp' => '2025-01-01T00:00:00Z' }])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({
                                                                                  total_actions: 10,
                                                                                  unique_actions: 2,
                                                                                  action_counts: { 'a' => 10 },
                                                                                  first_activity: '2025-01-01T00:00:00Z',
                                                                                  last_activity: '2025-01-02T00:00:00Z',
                                                                                  most_frequent: 'a'
                                                                                })

        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({
                                                                                  total_actions: 5,
                                                                                  unique_actions: 1,
                                                                                  action_counts: { 'b' => 5 },
                                                                                  first_activity: '2025-01-01T00:00:00Z',
                                                                                  last_activity: '2025-01-01T00:00:00Z',
                                                                                  most_frequent: 'b'
                                                                                })

        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'a',
                                                              'timestamp' => '2025-01-01T00:00:00Z' }]).and_return(80.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'b',
                                                              'timestamp' => '2025-01-01T00:00:00Z' }]).and_return(50.0)

        result = reporter.compare_users(%w[u1 u2])

        expect(result[:total_users]).to eq(2)
        expect(result[:top_user]).to eq('u1')
        expect(result[:average_score]).to eq(65.0)

        expect(result[:comparisons].length).to eq(2)
        # Sorted descending by engagement_score
        expect(result[:comparisons][0][:user_id]).to eq('u1')
        expect(result[:comparisons][0][:total_actions]).to eq(10)
        expect(result[:comparisons][0][:engagement_score]).to eq(80.0)
        expect(result[:comparisons][0][:most_frequent_action]).to eq('a')

        expect(result[:comparisons][1][:user_id]).to eq('u2')
        expect(result[:comparisons][1][:total_actions]).to eq(5)
        expect(result[:comparisons][1][:engagement_score]).to eq(50.0)
        expect(result[:comparisons][1][:most_frequent_action]).to eq('b')
      end
    end

    context 'with more than two users' do
      it 'handles multiple users correctly' do
        user_ids = %w[u1 u2 u3]

        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{ 'action' => 'a',
                                                                                    'timestamp' => '2025-01-01T00:00:00Z' }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{ 'action' => 'b',
                                                                                    'timestamp' => '2025-01-01T00:00:00Z' }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([{ 'action' => 'c',
                                                                                    'timestamp' => '2025-01-01T00:00:00Z' }])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 10, unique_actions: 2,
                                                                                  action_counts: {}, first_activity: '', last_activity: '', most_frequent: 'a' })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 20, unique_actions: 3,
                                                                                  action_counts: {}, first_activity: '', last_activity: '', most_frequent: 'b' })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 5, unique_actions: 1,
                                                                                  action_counts: {}, first_activity: '', last_activity: '', most_frequent: 'c' })

        allow(reporter).to receive(:fetch_user_score).with(anything).and_return(0.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'a',
                                                              'timestamp' => '2025-01-01T00:00:00Z' }]).and_return(30.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'b',
                                                              'timestamp' => '2025-01-01T00:00:00Z' }]).and_return(70.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'c',
                                                              'timestamp' => '2025-01-01T00:00:00Z' }]).and_return(50.0)

        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:top_user]).to eq('u2')
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[u2 u3 u1])
        expect(result[:average_score]).to eq(((70.0 + 50.0 + 30.0) / 3.0).round(2))
      end
    end
  end
end
