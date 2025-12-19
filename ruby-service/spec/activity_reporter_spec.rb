require 'spec_helper'
require 'json'
require 'tmpdir'
require 'rails_helper'

RSpec.describe ActivityReporter do
  describe '#initialize' do
    context 'with default URLs' do
      let(:reporter) do
        described_class.new
      end

      it 'sets the default Go and Python service URLs' do
        expect(reporter.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
        expect(reporter.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
      end
    end

    context 'with custom URLs' do
      let(:reporter) do
        described_class.new(go_service_url: 'http://go.example.com', python_service_url: 'http://py.example.com')
      end

      it 'sets the provided service URLs' do
        expect(reporter.instance_variable_get(:@go_service_url)).to eq('http://go.example.com')
        expect(reporter.instance_variable_get(:@python_service_url)).to eq('http://py.example.com')
      end
    end
  end

  describe '#generate_report' do
    let(:reporter) do
      described_class.new
    end

    context 'when the user has no activities' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([])
      end

      it 'returns an error report' do
        report = reporter.generate_report('u1')
        expect(report[:error]).to be true
        expect(report[:message]).to eq('No activities found')
        expect(report[:generated_at]).to be_a(String)
      end
    end

    context 'with activities and full data' do
      let(:fixed_time) do
        Time.utc(2023, 10, 3, 12, 0, 0)
      end

      let(:activities) do
        [
          { 'timestamp' => '2023-10-01T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2023-10-01T12:30:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-10-02T09:00:00Z', 'action' => 'click' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 2,
          action_counts: { 'login' => 1, 'click' => 2 },
          first_activity: '2023-10-01T10:15:00Z',
          last_activity: '2023-10-02T09:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'burst', 'description' => 'Short bursts of clicks', 'confidence' => 0.92 },
          { 'pattern_type' => 'daily', 'description' => 'Daily login', 'confidence' => 0.85 },
          { 'pattern_type' => 'weekly', 'description' => 'Weekly summary views', 'confidence' => 0.8 }
        ]
      end

      let(:user_score) do
        80.5
      end

      let(:anomalies) do
        [{ id: 1 }, { id: 2 }]
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_time)
        allow(reporter).to receive(:fetch_user_activities).with('user123').and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with('user123').and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'returns a comprehensive report with summary, patterns, anomalies, timeline, and insights' do
        report = reporter.generate_report('user123', group_by: :day)
        expect(report[:user_id]).to eq('user123')
        expect(report[:generated_at]).to eq(fixed_time.iso8601)

        expect(report[:summary][:total_actions]).to eq(3)
        expect(report[:summary][:unique_actions]).to eq(2)
        expect(report[:summary][:engagement_score]).to eq(80.5)
        expect(report[:summary][:first_activity]).to eq('2023-10-01T10:15:00Z')
        expect(report[:summary][:last_activity]).to eq('2023-10-02T09:00:00Z')

        expect(report[:action_breakdown]).to eq({ 'login' => 1, 'click' => 2 })

        expect(report[:patterns]).to eq([
                                          { type: 'burst', description: 'Short bursts of clicks', confidence: 0.92 },
                                          { type: 'daily', description: 'Daily login', confidence: 0.85 },
                                          { type: 'weekly', description: 'Weekly summary views', confidence: 0.8 }
                                        ])

        expect(report[:anomalies]).to eq(anomalies)

        expect(report[:timeline]).to eq([
                                          {
                                            period: '2023-10-01',
                                            total_actions: 2,
                                            actions: { 'login' => 1, 'click' => 1 },
                                            first_timestamp: '2023-10-01T10:15:00Z',
                                            last_timestamp: '2023-10-01T12:30:00Z'
                                          },
                                          {
                                            period: '2023-10-02',
                                            total_actions: 1,
                                            actions: { 'click' => 1 },
                                            first_timestamp: '2023-10-02T09:00:00Z',
                                            last_timestamp: '2023-10-02T09:00:00Z'
                                          }
                                        ])

        expect(report[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(report[:insights]).to include('Clear behavioral patterns detected')
        expect(report[:insights]).to include('2 anomalous activities detected - review recommended')
      end
    end

    context 'insights reflect low engagement, diversity, anomalies, and power user' do
      let(:activities) do
        [
          { 'timestamp' => '2023-10-05T10:00:00Z', 'action' => 'a1' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 11,
          action_counts: { 'a1' => 150 },
          first_activity: '2023-10-05T10:00:00Z',
          last_activity: '2023-10-05T10:00:00Z',
          most_frequent: 'a1'
        }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).and_return([])
        allow(reporter).to receive(:fetch_user_score).and_return(20.0)
        allow(reporter).to receive(:fetch_anomalies).and_return([{ id: 'x' }])
      end

      it 'includes appropriate low engagement, diversity, anomaly, and power user insights' do
        report = reporter.generate_report('low_user')
        expect(report[:insights]).to include('Low engagement - consider re-engagement strategies')
        expect(report[:insights]).to include('Diverse activity profile across multiple action types')
        expect(report[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(report[:insights]).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) do
      described_class.new
    end

    context 'when activities are empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([])
        expect(result).to eq([])
      end
    end

    context 'grouped by day' do
      let(:activities) do
        [
          { 'timestamp' => '2023-09-30T23:30:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-10-01T01:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-10-01T10:00:00Z', 'action' => 'view' }
        ]
      end

      it 'groups activities into daily buckets with sorted periods' do
        result = reporter.format_timeline(activities, :day)
        expect(result).to eq([
                               {
                                 period: '2023-09-30',
                                 total_actions: 1,
                                 actions: { 'view' => 1 },
                                 first_timestamp: '2023-09-30T23:30:00Z',
                                 last_timestamp: '2023-09-30T23:30:00Z'
                               },
                               {
                                 period: '2023-10-01',
                                 total_actions: 2,
                                 actions: { 'click' => 1, 'view' => 1 },
                                 first_timestamp: '2023-10-01T01:00:00Z',
                                 last_timestamp: '2023-10-01T10:00:00Z'
                               }
                             ])
      end
    end

    context 'grouped by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2023-10-02T09:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2023-10-02T09:45:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-10-02T10:05:00Z', 'action' => 'logout' }
        ]
      end

      it 'groups activities into hourly buckets and formats period as YYYY-MM-DD HH:00' do
        result = reporter.format_timeline(activities, :hour)
        expect(result).to eq([
                               {
                                 period: '2023-10-02 09:00',
                                 total_actions: 2,
                                 actions: { 'login' => 1, 'click' => 1 },
                                 first_timestamp: '2023-10-02T09:15:00Z',
                                 last_timestamp: '2023-10-02T09:45:00Z'
                               },
                               {
                                 period: '2023-10-02 10:00',
                                 total_actions: 1,
                                 actions: { 'logout' => 1 },
                                 first_timestamp: '2023-10-02T10:05:00Z',
                                 last_timestamp: '2023-10-02T10:05:00Z'
                               }
                             ])
      end
    end

    context 'grouped by week' do
      let(:activities) do
        [
          { 'timestamp' => '2023-10-04T12:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-10-10T12:00:00Z', 'action' => 'click' }
        ]
      end

      it 'groups activities into ISO week buckets' do
        result = reporter.format_timeline(activities, :week)
        expect(result).to eq([
                               {
                                 period: '2023-W40',
                                 total_actions: 1,
                                 actions: { 'view' => 1 },
                                 first_timestamp: '2023-10-04T12:00:00Z',
                                 last_timestamp: '2023-10-04T12:00:00Z'
                               },
                               {
                                 period: '2023-W41',
                                 total_actions: 1,
                                 actions: { 'click' => 1 },
                                 first_timestamp: '2023-10-10T12:00:00Z',
                                 last_timestamp: '2023-10-10T12:00:00Z'
                               }
                             ])
      end
    end

    context 'grouped by month' do
      let(:activities) do
        [
          { 'timestamp' => '2023-08-31T23:59:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-09-01T00:01:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-09-15T10:00:00Z', 'action' => 'click' }
        ]
      end

      it 'groups activities into monthly buckets' do
        result = reporter.format_timeline(activities, :month)
        expect(result).to eq([
                               {
                                 period: '2023-08',
                                 total_actions: 1,
                                 actions: { 'view' => 1 },
                                 first_timestamp: '2023-08-31T23:59:00Z',
                                 last_timestamp: '2023-08-31T23:59:00Z'
                               },
                               {
                                 period: '2023-09',
                                 total_actions: 2,
                                 actions: { 'view' => 1, 'click' => 1 },
                                 first_timestamp: '2023-09-01T00:01:00Z',
                                 last_timestamp: '2023-09-15T10:00:00Z'
                               }
                             ])
      end
    end

    context 'with unknown group_by value' do
      let(:activities) do
        [
          { 'timestamp' => '2023-10-01T12:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2023-10-02T12:00:00Z', 'action' => 'b' }
        ]
      end

      it 'falls back to daily grouping' do
        result = reporter.format_timeline(activities, :unknown)
        expect(result.map do |e|
          e[:period]
        end).to eq(%w[2023-10-01 2023-10-02])
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
        summary: { total_actions: 2 },
        data: [1, 2, 3]
      }
    end

    context 'when no filepath is provided' do
      it 'returns pretty JSON data' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be true
        expect(result[:data]).to eq(JSON.pretty_generate(report))
        expect(result[:filepath]).to be_nil
      end
    end

    context 'when a filepath is provided' do
      it 'writes the JSON to disk and returns file info' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(path)
          expect(File.exist?(path)).to be true
          content = File.read(path)
          expect(content).to eq(JSON.pretty_generate(report))
          expect(result[:size]).to eq(content.bytesize)
        end
      end
    end

    context 'when writing fails' do
      it 'returns a failure result with the error message' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        result = reporter.export_to_json(report, '/unwritable/path.json')
        expect(result[:success]).to be false
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    let(:reporter) do
      described_class.new
    end

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only_one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with multiple users and varying scores' do
      let(:user_ids) do
        %w[u1 u2 u3]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{
                                                                                   'timestamp' => '2023-10-01T00:00:00Z', 'action' => 'a'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{
                                                                                   'timestamp' => '2023-10-02T00:00:00Z', 'action' => 'b'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([{
                                                                                   'timestamp' => '2023-10-03T00:00:00Z', 'action' => 'c'
                                                                                 }])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 10, unique_actions: 3,
                                                                                  action_counts: { 'a' => 10 }, first_activity: 't1', last_activity: 't1', most_frequent: 'a' })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 5, unique_actions: 2,
                                                                                  action_counts: { 'b' => 5 }, first_activity: 't2', last_activity: 't2', most_frequent: 'b' })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 8, unique_actions: 2,
                                                                                  action_counts: { 'c' => 8 }, first_activity: 't3', last_activity: 't3', most_frequent: 'c' })

        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2023-10-01T00:00:00Z',
                                                              'action' => 'a' }]).and_return(80.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2023-10-02T00:00:00Z',
                                                              'action' => 'b' }]).and_return(30.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2023-10-03T00:00:00Z',
                                                              'action' => 'c' }]).and_return(50.0)
      end

      it 'returns comparisons sorted by engagement score descending with top user and average score' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map do |c|
          c[:user_id]
        end).to eq(%w[u1 u3 u2])
        expect(result[:comparisons].first[:most_frequent_action]).to eq('a')
        expect(result[:top_user]).to eq('u1')
        expect(result[:average_score]).to eq(53.33)
      end
    end

    context 'when users have equal scores' do
      let(:user_ids) do
        %w[b a]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('b').and_return([{
                                                                                  'timestamp' => '2023-10-01T00:00:00Z', 'action' => 'x'
                                                                                }])
        allow(reporter).to receive(:fetch_user_activities).with('a').and_return([{
                                                                                  'timestamp' => '2023-10-01T00:00:00Z', 'action' => 'y'
                                                                                }])

        allow(reporter).to receive(:fetch_activity_stats).with('b').and_return({ total_actions: 1, unique_actions: 1,
                                                                                 action_counts: { 'x' => 1 }, first_activity: 't', last_activity: 't', most_frequent: 'x' })
        allow(reporter).to receive(:fetch_activity_stats).with('a').and_return({ total_actions: 1, unique_actions: 1,
                                                                                 action_counts: { 'y' => 1 }, first_activity: 't', last_activity: 't', most_frequent: 'y' })

        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2023-10-01T00:00:00Z',
                                                              'action' => 'x' }]).and_return(50.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2023-10-01T00:00:00Z',
                                                              'action' => 'y' }]).and_return(50.0)
      end

      it 'keeps original order for equal scores' do
        result = reporter.compare_users(user_ids)
        expect(result[:comparisons].map do |c|
          c[:user_id]
        end).to eq(%w[b a])
        expect(result[:top_user]).to eq('b')
        expect(result[:average_score]).to eq(50.0)
      end
    end
  end
end
