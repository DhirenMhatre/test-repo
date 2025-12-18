require 'spec_helper'
require 'time'
require 'tempfile'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  describe '#initialize' do
    context 'with defaults' do
      let(:reporter) do
        described_class.new
      end

      it 'sets default service URLs' do
        expect(reporter.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
        expect(reporter.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
      end
    end

    context 'with custom URLs' do
      let(:go_url) do
        'http://go.example.com:9000'
      end

      let(:py_url) do
        'http://py.example.com:9100'
      end

      let(:reporter) do
        described_class.new(go_service_url: go_url, python_service_url: py_url)
      end

      it 'applies custom URLs' do
        expect(reporter.instance_variable_get(:@go_service_url)).to eq(go_url)
        expect(reporter.instance_variable_get(:@python_service_url)).to eq(py_url)
      end
    end
  end

  describe '#generate_report' do
    let(:reporter) do
      described_class.new
    end

    let(:fixed_time) do
      Time.utc(2023, 3, 1, 14, 0, 0)
    end

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report('u1')
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with activities and high engagement' do
      let(:activities) do
        [
          { 'action' => 'a', 'timestamp' => '2023-03-01T10:00:00Z' },
          { 'action' => 'b', 'timestamp' => '2023-03-01T12:00:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 2,
          unique_actions: 2,
          action_counts: { 'a' => 1, 'b' => 1 },
          first_activity: '2023-03-01T10:00:00Z',
          last_activity: '2023-03-01T12:00:00Z',
          most_frequent: 'a'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'sequence', 'description' => 'a then b', 'confidence' => 0.9 },
          { 'pattern_type' => 'burst', 'description' => 'rapid', 'confidence' => 0.8 },
          { 'pattern_type' => 'time', 'description' => 'morning', 'confidence' => 0.7 }
        ]
      end

      let(:anomalies) do
        ['odd']
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(80.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'returns a comprehensive report with expected fields and insights' do
        result = reporter.generate_report('u1', group_by: :hour)
        expect(result[:user_id]).to eq('u1')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)

        expect(result[:summary][:total_actions]).to eq(2)
        expect(result[:summary][:unique_actions]).to eq(2)
        expect(result[:summary][:engagement_score]).to eq(80.0)
        expect(result[:summary][:first_activity]).to eq('2023-03-01T10:00:00Z')
        expect(result[:summary][:last_activity]).to eq('2023-03-01T12:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'a' => 1, 'b' => 1 })

        expect(result[:patterns]).to eq([
                                          { type: 'sequence', description: 'a then b', confidence: 0.9 },
                                          { type: 'burst', description: 'rapid', confidence: 0.8 },
                                          { type: 'time', description: 'morning', confidence: 0.7 }
                                        ])

        expect(result[:anomalies]).to eq(['odd'])

        periods = result[:timeline].map do |entry|
          entry[:period]
        end
        expect(periods).to eq(['2023-03-01 10:00', '2023-03-01 12:00'])

        expect(result[:timeline][0][:actions]).to eq({ 'a' => 1 })
        expect(result[:timeline][1][:actions]).to eq({ 'b' => 1 })
        expect(result[:timeline][0][:total_actions]).to eq(1)
        expect(result[:timeline][1][:total_actions]).to eq(1)

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(result[:insights]).not_to include('Power user - high volume of activities')
      end
    end

    context 'with moderate engagement and diverse, high-volume activity' do
      let(:activities) do
        [
          { 'action' => 'x', 'timestamp' => '2023-03-02T10:00:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 11,
          action_counts: { 'x' => 150 },
          first_activity: '2023-03-02T10:00:00Z',
          last_activity: '2023-03-02T10:00:00Z',
          most_frequent: 'x'
        }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return([])
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(60.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([])
      end

      it 'includes moderate engagement, diversity, and power user insights' do
        result = reporter.generate_report('u2', group_by: :day)
        expect(result[:insights]).to include('Moderately engaged user with regular activity')
        expect(result[:insights]).to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).to include('Power user - high volume of activities')
        expect(result[:insights]).not_to include('Clear behavioral patterns detected')
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) do
      described_class.new
    end

    context 'with empty activities' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'grouped by hour' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2023-01-01T09:15:00Z' },
          { 'action' => 'click', 'timestamp' => '2023-01-01T09:45:00Z' },
          { 'action' => 'click', 'timestamp' => '2023-01-01T10:15:00Z' },
          { 'action' => 'logout', 'timestamp' => '2023-01-02T11:00:00Z' }
        ]
      end

      it 'buckets into hours and sorts by period' do
        timeline = reporter.format_timeline(activities, :hour)
        periods = timeline.map do |entry|
          entry[:period]
        end
        expect(periods).to eq(['2023-01-01 09:00', '2023-01-01 10:00', '2023-01-02 11:00'])
        expect(timeline[0][:total_actions]).to eq(2)
        expect(timeline[0][:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(timeline[0][:first_timestamp]).to eq('2023-01-01T09:15:00Z')
        expect(timeline[0][:last_timestamp]).to eq('2023-01-01T09:45:00Z')
      end
    end

    context 'grouped by day' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2023-01-01T09:15:00Z' },
          { 'action' => 'click', 'timestamp' => '2023-01-01T10:15:00Z' },
          { 'action' => 'logout', 'timestamp' => '2023-01-02T11:00:00Z' }
        ]
      end

      it 'buckets into days' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.map do |e|
          e[:period]
        end).to eq(%w[2023-01-01 2023-01-02])
        expect(timeline[0][:total_actions]).to eq(2)
        expect(timeline[1][:total_actions]).to eq(1)
      end
    end

    context 'grouped by week' do
      let(:activities) do
        [
          { 'action' => 'a', 'timestamp' => '2023-06-12T10:00:00Z' },
          { 'action' => 'b', 'timestamp' => '2023-06-14T11:00:00Z' },
          { 'action' => 'c', 'timestamp' => '2023-06-20T12:00:00Z' }
        ]
      end

      it 'buckets into weeks using %Y-W%V format' do
        timeline = reporter.format_timeline(activities, :week)
        expect(timeline.map do |e|
          e[:period]
        end).to eq(%w[2023-W24 2023-W25])
        counts = timeline.map do |e|
          e[:total_actions]
        end
        expect(counts).to eq([2, 1])
      end
    end

    context 'grouped by month' do
      let(:activities) do
        [
          { 'action' => 'a', 'timestamp' => '2023-05-10T10:00:00Z' },
          { 'action' => 'b', 'timestamp' => '2023-06-10T10:00:00Z' }
        ]
      end

      it 'buckets into months' do
        timeline = reporter.format_timeline(activities, :month)
        expect(timeline.map do |e|
          e[:period]
        end).to eq(%w[2023-05 2023-06])
        expect(timeline[0][:total_actions]).to eq(1)
        expect(timeline[1][:total_actions]).to eq(1)
      end
    end

    context 'with unknown group_by' do
      let(:activities) do
        [
          { 'action' => 'x', 'timestamp' => '2023-01-01T00:00:00Z' },
          { 'action' => 'y', 'timestamp' => '2023-01-02T00:00:00Z' }
        ]
      end

      it 'defaults to grouping by day' do
        timeline = reporter.format_timeline(activities, :unknown)
        expect(timeline.map do |e|
          e[:period]
        end).to eq(%w[2023-01-01 2023-01-02])
      end
    end

    context 'with invalid timestamp strings' do
      let(:fixed_time) do
        Time.utc(2024, 1, 15, 8, 30, 0)
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_time)
      end

      let(:activities) do
        [
          { 'action' => 'bad', 'timestamp' => 'not-a-time' }
        ]
      end

      it 'falls back to Time.now without raising and groups accordingly' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.length).to eq(1)
        expect(timeline[0][:period]).to eq(fixed_time.strftime('%Y-%m-%d'))
        expect(timeline[0][:actions]).to eq({ 'bad' => 1 })
        expect(timeline[0][:first_timestamp]).to eq('not-a-time')
        expect(timeline[0][:last_timestamp]).to eq('not-a-time')
      end
    end
  end

  describe '#export_to_json' do
    let(:reporter) do
      described_class.new
    end

    let(:report) do
      {
        user_id: 'u1',
        summary: {
          total_actions: 2
        }
      }
    end

    context 'when filepath is not provided' do
      it 'returns JSON in data field' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be true
        expect(result[:data]).to be_a(String)
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq('u1')
        expect(parsed['summary']['total_actions']).to eq(2)
      end
    end

    context 'when filepath is provided' do
      it 'writes the file and returns metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(path)
          expect(result[:size]).to be > 0
          content = File.read(path)
          parsed = JSON.parse(content)
          expect(parsed['user_id']).to eq('u1')
        end
      end
    end

    context 'when writing fails' do
      it 'returns an error result' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        result = reporter.export_to_json(report, '/tmp/any.json')
        expect(result[:success]).to be false
        expect(result[:error]).to match(/disk full/)
      end
    end
  end

  describe '#compare_users' do
    let(:reporter) do
      described_class.new
    end

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with multiple users' do
      let(:user_ids) do
        %w[u1 u2 u3]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{ 'action' => 'a' }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{ 'action' => 'b' },
                                                                                  { 'action' => 'b' }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([{ 'action' => 'c' },
                                                                                  { 'action' => 'c' }, { 'action' => 'c' }])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 1, unique_actions: 1,
                                                                                  action_counts: { 'a' => 1 }, first_activity: 't', last_activity: 't', most_frequent: 'a' })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 2, unique_actions: 1,
                                                                                  action_counts: { 'b' => 2 }, first_activity: 't', last_activity: 't', most_frequent: 'b' })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 3, unique_actions: 1,
                                                                                  action_counts: { 'c' => 3 }, first_activity: 't', last_activity: 't', most_frequent: 'c' })

        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'a' }]).and_return(50.5)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'b' }, { 'action' => 'b' }]).and_return(88.25)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'c' }, { 'action' => 'c' },
                                                            { 'action' => 'c' }]).and_return(70.0)
      end

      it 'sorts users by engagement_score descending and computes average' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)

        comparisons = result[:comparisons]
        expect(comparisons.map do |c|
          c[:user_id]
        end).to eq(%w[u2 u3 u1])

        expect(comparisons.first[:engagement_score]).to eq(88.25)
        expect(comparisons.first[:most_frequent_action]).to eq('b')
        expect(result[:top_user]).to eq('u2')

        avg = ((88.25 + 70.0 + 50.5) / 3.0).round(2)
        expect(result[:average_score]).to eq(avg)
      end
    end

    context 'with tie scores preserves input order for ties' do
      let(:user_ids) do
        %w[a b]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('a').and_return([{ 'action' => 'x' }])
        allow(reporter).to receive(:fetch_user_activities).with('b').and_return([{ 'action' => 'y' }])

        allow(reporter).to receive(:fetch_activity_stats).with('a').and_return({ total_actions: 1, unique_actions: 1,
                                                                                 action_counts: { 'x' => 1 }, first_activity: 't', last_activity: 't', most_frequent: 'x' })
        allow(reporter).to receive(:fetch_activity_stats).with('b').and_return({ total_actions: 1, unique_actions: 1,
                                                                                 action_counts: { 'y' => 1 }, first_activity: 't', last_activity: 't', most_frequent: 'y' })

        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'x' }]).and_return(50.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'y' }]).and_return(50.0)
      end

      it 'keeps the original order when scores are equal' do
        result = reporter.compare_users(user_ids)
        ids = result[:comparisons].map do |c|
          c[:user_id]
        end
        expect(ids).to eq(%w[a b])
      end
    end
  end
end
