require 'spec_helper'
require 'json'
require 'time'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  describe '#initialize' do
    context 'with default URLs' do
      let(:reporter) { described_class.new }

      it 'sets default service URLs' do
        expect(reporter.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
        expect(reporter.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
      end
    end

    context 'with custom URLs' do
      let(:go_url) { 'http://go.example.com:9090' }
      let(:py_url) { 'http://py.example.com:9091' }
      let(:reporter) { described_class.new(go_service_url: go_url, python_service_url: py_url) }

      it 'stores provided service URLs' do
        expect(reporter.instance_variable_get(:@go_service_url)).to eq(go_url)
        expect(reporter.instance_variable_get(:@python_service_url)).to eq(py_url)
      end
    end
  end

  describe '#generate_report' do
    let(:reporter) { described_class.new }

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([])
      end

      it 'returns an error report with message and timestamp' do
        fixed_time = Time.utc(2023, 1, 1, 12, 0, 0)
        allow(Time).to receive(:now).and_return(fixed_time)

        result = reporter.generate_report('u1')

        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with activities and full data' do
      let(:user_id) { 'user-123' }
      let(:activities) do
        [
          { 'timestamp' => '2023-05-01T10:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2023-05-01T12:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-05-02T09:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-05-02T10:00:00Z', 'action' => 'purchase' }
        ]
      end
      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 12,
          action_counts: { 'login' => 10, 'click' => 120, 'purchase' => 20 },
          first_activity: '2023-05-01T10:00:00Z',
          last_activity: '2023-05-02T10:00:00Z',
          most_frequent: 'click'
        }
      end
      let(:patterns) do
        [
          { 'pattern_type' => 'sequence', 'description' => 'login->click', 'confidence' => 0.9 },
          { 'pattern_type' => 'time', 'description' => 'morning activity', 'confidence' => 0.8 },
          { 'pattern_type' => 'cluster', 'description' => 'engaged cohort', 'confidence' => 0.75 }
        ]
      end
      let(:anomalies) { [{ 'id' => 1, 'reason' => 'suspicious time' }] }
      let(:score) { 80.5 }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
        allow(Time).to receive(:now).and_return(Time.utc(2023, 5, 3, 0, 0, 0))
      end

      it 'builds a comprehensive report including summary, patterns, anomalies, timeline, and insights' do
        report = reporter.generate_report(user_id, group_by: :day)

        expect(report[:user_id]).to eq(user_id)
        expect(report[:generated_at]).to eq(Time.now.iso8601)

        expect(report[:summary][:total_actions]).to eq(150)
        expect(report[:summary][:unique_actions]).to eq(12)
        expect(report[:summary][:first_activity]).to eq('2023-05-01T10:00:00Z')
        expect(report[:summary][:last_activity]).to eq('2023-05-02T10:00:00Z')
        expect(report[:summary][:engagement_score]).to eq(80.5)

        expect(report[:action_breakdown]).to eq({ 'login' => 10, 'click' => 120, 'purchase' => 20 })

        expect(report[:patterns]).to eq([
                                          { type: 'sequence', description: 'login->click', confidence: 0.9 },
                                          { type: 'time', description: 'morning activity', confidence: 0.8 },
                                          { type: 'cluster', description: 'engaged cohort', confidence: 0.75 }
                                        ])

        expect(report[:anomalies]).to eq(anomalies)

        expect(report[:timeline].size).to eq(2)
        expect(report[:timeline].first[:period]).to eq('2023-05-01')
        expect(report[:timeline].first[:total_actions]).to eq(2)
        expect(report[:timeline].first[:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(report[:timeline].first[:first_timestamp]).to eq('2023-05-01T10:00:00Z')
        expect(report[:timeline].first[:last_timestamp]).to eq('2023-05-01T12:00:00Z')
        expect(report[:timeline].last[:period]).to eq('2023-05-02')
        expect(report[:timeline].last[:total_actions]).to eq(2)
        expect(report[:timeline].last[:actions]).to eq({ 'click' => 1, 'purchase' => 1 })

        expect(report[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(report[:insights]).to include('Diverse activity profile across multiple action types')
        expect(report[:insights]).to include('Clear behavioral patterns detected')
        expect(report[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(report[:insights]).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) { described_class.new }

    context 'when activities array is empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([], :day)
        expect(result).to eq([])
      end
    end

    context 'when grouping by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2023-06-10T10:15:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-06-10T10:45:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-06-10T11:05:00Z', 'action' => 'click' }
        ]
      end

      it 'aggregates into hourly buckets with proper counts and timestamps' do
        result = reporter.format_timeline(activities, :hour)
        expect(result.size).to eq(2)
        expect(result[0][:period]).to eq('2023-06-10 10:00')
        expect(result[0][:total_actions]).to eq(2)
        expect(result[0][:actions]).to eq({ 'view' => 1, 'click' => 1 })
        expect(result[0][:first_timestamp]).to eq('2023-06-10T10:15:00Z')
        expect(result[0][:last_timestamp]).to eq('2023-06-10T10:45:00Z')
        expect(result[1][:period]).to eq('2023-06-10 11:00')
        expect(result[1][:total_actions]).to eq(1)
        expect(result[1][:actions]).to eq({ 'click' => 1 })
      end
    end

    context 'when grouping by day' do
      let :activities do
        [
          { 'timestamp' => '2023-01-01T23:59:59Z', 'action' => 'view' },
          { 'timestamp' => '2023-01-02T00:00:01Z', 'action' => 'click' },
          { 'timestamp' => '2023-01-02T12:00:00Z', 'action' => 'view' }
        ]
      end

      it 'aggregates into daily buckets' do
        result = reporter.format_timeline(activities, :day)
        expect(result.map { |e| e[:period] }).to eq(%w[2023-01-01 2023-01-02])
        expect(result.find { |e| e[:period] == '2023-01-01' }[:actions]).to eq({ 'view' => 1 })
        expect(result.find { |e| e[:period] == '2023-01-02' }[:actions]).to eq({ 'click' => 1, 'view' => 1 })
      end
    end

    context 'when grouping by ISO week' do
      let :activities do
        [
          { 'timestamp' => '2023-01-02T10:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2023-01-03T10:00:00Z', 'action' => 'b' }
        ]
      end

      it 'aggregates into weekly buckets using ISO week format' do
        result = reporter.format_timeline(activities, :week)
        expect(result.size).to eq(1)
        expect(result.first[:period]).to eq('2023-W01')
        expect(result.first[:total_actions]).to eq(2)
        expect(result.first[:actions]).to eq({ 'a' => 1, 'b' => 1 })
      end
    end

    context 'when grouping by month' do
      let :activities do
        [
          { 'timestamp' => '2023-02-01T00:00:00Z', 'action' => 'start' },
          { 'timestamp' => '2023-02-28T23:59:59Z', 'action' => 'end' },
          { 'timestamp' => '2023-03-01T00:00:00Z', 'action' => 'start' }
        ]
      end

      it 'aggregates into monthly buckets' do
        result = reporter.format_timeline(activities, :month)
        expect(result.map { |e| e[:period] }).to eq(%w[2023-02 2023-03])
        feb = result.find { |e| e[:period] == '2023-02' }
        mar = result.find { |e| e[:period] == '2023-03' }
        expect(feb[:total_actions]).to eq(2)
        expect(feb[:actions]).to eq({ 'start' => 1, 'end' => 1 })
        expect(mar[:total_actions]).to eq(1)
        expect(mar[:actions]).to eq({ 'start' => 1 })
      end
    end

    context 'when group_by is unknown' do
      let :activities do
        [
          { 'timestamp' => '2023-04-10T10:00:00Z', 'action' => 'x' },
          { 'timestamp' => '2023-04-11T10:00:00Z', 'action' => 'y' }
        ]
      end

      it 'defaults to daily grouping' do
        result = reporter.format_timeline(activities, :unknown)
        expect(result.map { |e| e[:period] }).to eq(%w[2023-04-10 2023-04-11])
      end
    end

    context 'when an activity has invalid timestamp' do
      it 'falls back to Time.now for grouping' do
        fixed_time = Time.utc(2023, 7, 1, 0, 0, 0)
        allow(Time).to receive(:now).and_return(fixed_time)
        activities = [{ 'timestamp' => 'not-a-time', 'action' => 'oops' }]
        result = reporter.format_timeline(activities, :day)
        expect(result.first[:period]).to eq('2023-07-01')
        expect(result.first[:actions]).to eq({ 'oops' => 1 })
      end
    end
  end

  describe '#export_to_json' do
    let(:reporter) { described_class.new }

    context 'when no filepath is provided' do
      it 'returns JSON data in the result' do
        report = { a: 1, b: { c: 2 } }
        result = reporter.export_to_json(report)
        expect(result[:success]).to be true
        expect(result[:data]).to eq(JSON.pretty_generate(report))
        expect(result[:filepath]).to be_nil
      end
    end

    context 'when a filepath is provided' do
      it 'writes JSON to the file and returns metadata' do
        require 'tmpdir'
        report = { user: 'u1', stats: { total: 10 } }
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(path)
          expected_json = JSON.pretty_generate(report)
          expect(File.read(path)).to eq(expected_json)
          expect(result[:size]).to eq(expected_json.bytesize)
        end
      end
    end

    context 'when write fails' do
      it 'returns an error response' do
        report = { x: 1 }
        filepath = '/tmp/does_not_matter.json'
        allow(File).to receive(:write).with(filepath, kind_of(String)).and_raise(StandardError.new('disk full'))
        result = reporter.export_to_json(report, filepath)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    let(:reporter) { described_class.new }

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        fixed_time = Time.utc(2023, 1, 1, 0, 0, 0)
        allow(Time).to receive(:now).and_return(fixed_time)
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with multiple users' do
      let(:user_ids) { %w[u1 u2 u3] }
      let(:stats_u1) do
        { total_actions: 10, unique_actions: 3, action_counts: { 'a' => 5 }, first_activity: '2023-01-01T00:00:00Z',
          last_activity: '2023-01-02T00:00:00Z', most_frequent: 'a' }
      end
      let(:stats_u2) do
        { total_actions: 20, unique_actions: 4, action_counts: { 'b' => 10 }, first_activity: '2023-01-01T00:00:00Z',
          last_activity: '2023-01-03T00:00:00Z', most_frequent: 'b' }
      end
      let(:stats_u3) do
        { total_actions: 5, unique_actions: 2, action_counts: { 'c' => 5 }, first_activity: '2023-01-01T00:00:00Z',
          last_activity: '2023-01-01T12:00:00Z', most_frequent: 'c' }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{
                                                                                   'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'a'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{
                                                                                   'timestamp' => '2023-01-02T00:00:00Z', 'action' => 'b'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([{
                                                                                   'timestamp' => '2023-01-03T00:00:00Z', 'action' => 'c'
                                                                                 }])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return(stats_u1)
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return(stats_u2)
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return(stats_u3)

        allow(reporter).to receive(:fetch_user_score).with(kind_of(Array)).and_return(55.5, 80.55, 10.0)
      end

      it 'returns users sorted by engagement score with summary metrics' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[u2 u1 u3])

        top = result[:comparisons].first
        expect(top[:user_id]).to eq('u2')
        expect(top[:engagement_score]).to eq(80.55)
        expect(top[:most_frequent_action]).to eq('b')

        expect(result[:top_user]).to eq('u2')

        expected_average = ((80.55 + 55.5 + 10.0) / 3.0).round(2)
        expect(result[:average_score]).to eq(expected_average)
      end
    end
  end
end
