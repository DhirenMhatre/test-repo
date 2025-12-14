require 'spec_helper'
require 'json'
require 'time'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  describe '#initialize' do
    context 'with default service URLs' do
      let(:reporter) do
        described_class.new
      end

      it 'sets default Go and Python service URLs' do
        go_url = reporter.instance_variable_get(:@go_service_url)
        py_url = reporter.instance_variable_get(:@python_service_url)
        expect(go_url).to eq('http://localhost:8080')
        expect(py_url).to eq('http://localhost:8081')
      end
    end

    context 'with custom service URLs' do
      let(:reporter) do
        described_class.new(go_service_url: 'http://go.example', python_service_url: 'http://py.example')
      end

      it 'uses provided service URLs' do
        go_url = reporter.instance_variable_get(:@go_service_url)
        py_url = reporter.instance_variable_get(:@python_service_url)
        expect(go_url).to eq('http://go.example')
        expect(py_url).to eq('http://py.example')
      end
    end
  end

  describe '#generate_report' do
    let(:reporter) do
      described_class.new
    end

    context 'when no activities are found' do
      let(:fixed_time) do
        Time.parse('2023-01-01T00:00:00Z')
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_time)
        allow(reporter).to receive(:fetch_user_activities).with(123).and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report(123)
        expect(result[:error]).to be(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'when activities are present and group_by is hour' do
      let(:fixed_time) do
        Time.parse('2023-05-16T12:00:00Z')
      end

      let(:activities) do
        [
          { 'timestamp' => '2023-05-10T10:15:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-05-10T10:45:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-05-10T11:00:00Z', 'action' => 'click' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 11,
          action_counts: { 'click' => 90, 'view' => 60 },
          first_activity: '2023-05-01T00:00:00Z',
          last_activity: '2023-05-15T00:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'sequence', 'description' => 'A->B->C', 'confidence' => 0.91 },
          { 'pattern_type' => 'burst', 'description' => 'High activity at noon', 'confidence' => 0.74 },
          { 'pattern_type' => 'trend', 'description' => 'Rising daily actions', 'confidence' => 0.87 }
        ]
      end

      let(:anomalies) do
        ['unexpected spike', 'suspicious login']
      end

      let(:user_score) do
        80.5
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_time)
        allow(reporter).to receive(:fetch_user_activities).with('user-1').and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with('user-1').and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'returns a comprehensive report with summary, patterns, anomalies, timeline, and insights' do
        result = reporter.generate_report('user-1', group_by: :hour)
        expect(result[:user_id]).to eq('user-1')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)

        expect(result[:summary][:total_actions]).to eq(150)
        expect(result[:summary][:unique_actions]).to eq(11)
        expect(result[:summary][:engagement_score]).to eq(80.5)
        expect(result[:summary][:first_activity]).to eq('2023-05-01T00:00:00Z')
        expect(result[:summary][:last_activity]).to eq('2023-05-15T00:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'click' => 90, 'view' => 60 })

        expect(result[:patterns]).to contain_exactly(
          { type: 'sequence', description: 'A->B->C', confidence: 0.91 },
          { type: 'burst', description: 'High activity at noon', confidence: 0.74 },
          { type: 'trend', description: 'Rising daily actions', confidence: 0.87 }
        )

        expect(result[:anomalies]).to eq(anomalies)

        periods = result[:timeline].map do |entry|
          entry[:period]
        end
        expect(periods).to eq(['2023-05-10 10:00', '2023-05-10 11:00'])

        first_bucket = result[:timeline].find do |entry|
          entry[:period] == '2023-05-10 10:00'
        end
        expect(first_bucket[:total_actions]).to eq(2)
        expect(first_bucket[:actions]).to eq({ 'click' => 1, 'view' => 1 })
        expect(first_bucket[:first_timestamp]).to eq('2023-05-10T10:15:00Z')
        expect(first_bucket[:last_timestamp]).to eq('2023-05-10T10:45:00Z')

        insights = result[:insights]
        expect(insights).to include('Highly engaged user with strong activity patterns')
        expect(insights).to include('Diverse activity profile across multiple action types')
        expect(insights).to include('Clear behavioral patterns detected')
        expect(insights).to include('2 anomalous activities detected - review recommended')
        expect(insights).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) do
      described_class.new
    end

    context 'with empty activities' do
      it 'returns an empty array' do
        result = reporter.format_timeline([])
        expect(result).to eq([])
      end
    end

    context 'grouped by day' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-10T08:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-05-10T09:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-05-11T10:00:00Z', 'action' => 'click' }
        ]
      end

      it 'groups activities by day and sorts by period' do
        result = reporter.format_timeline(activities, :day)
        expect(result.length).to eq(2)
        expect(result[0][:period]).to eq('2023-05-10')
        expect(result[0][:total_actions]).to eq(2)
        expect(result[0][:actions]).to eq({ 'click' => 1, 'view' => 1 })
        expect(result[1][:period]).to eq('2023-05-11')
        expect(result[1][:total_actions]).to eq(1)
        expect(result[1][:actions]).to eq({ 'click' => 1 })
      end
    end

    context 'grouped by week' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-08T08:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-05-14T12:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-05-15T09:00:00Z', 'action' => 'click' }
        ]
      end

      it 'groups activities by ISO week' do
        result = reporter.format_timeline(activities, :week)
        periods = result.map do |e|
          e[:period]
        end
        expect(periods).to eq(%w[2023-W19 2023-W20])
        w19 = result.find do |e|
          e[:period] == '2023-W19'
        end
        w20 = result.find do |e|
          e[:period] == '2023-W20'
        end
        expect(w19[:total_actions]).to eq(2)
        expect(w20[:total_actions]).to eq(1)
      end
    end

    context 'grouped by month' do
      let(:activities) do
        [
          { 'timestamp' => '2023-04-30T23:59:59Z', 'action' => 'view' },
          { 'timestamp' => '2023-05-01T00:00:00Z', 'action' => 'click' }
        ]
      end

      it 'groups activities by month' do
        result = reporter.format_timeline(activities, :month)
        periods = result.map do |e|
          e[:period]
        end
        expect(periods).to eq(%w[2023-04 2023-05])
      end
    end

    context 'with unknown group_by value' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-10T08:00:00Z', 'action' => 'click' }
        ]
      end

      it 'falls back to day grouping' do
        result = reporter.format_timeline(activities, :unknown)
        expect(result.length).to eq(1)
        expect(result[0][:period]).to eq('2023-05-10')
      end
    end

    context 'with invalid timestamp values' do
      let(:activities) do
        [
          { 'timestamp' => 'not-a-time', 'action' => 'click' }
        ]
      end

      let(:fixed_now) do
        Time.parse('2023-01-02T03:04:05Z')
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_now)
      end

      it 'uses current time for grouping and retains original timestamps' do
        result = reporter.format_timeline(activities, :day)
        expect(result.length).to eq(1)
        expect(result[0][:period]).to eq('2023-01-02')
        expect(result[0][:first_timestamp]).to eq('not-a-time')
        expect(result[0][:last_timestamp]).to eq('not-a-time')
      end
    end
  end

  describe '#export_to_json' do
    let(:reporter) do
      described_class.new
    end

    context 'when filepath is provided' do
      let(:report) do
        { a: 1, b: { c: 2 } }
      end

      let(:filepath) do
        File.join(Dir.pwd, 'tmp_activity_report_test.json')
      end

      it 'writes pretty JSON to file and returns metadata' do
        expected_json = JSON.pretty_generate(report)
        allow(File).to receive(:write).and_return(expected_json.length)
        result = reporter.export_to_json(report, filepath)
        expect(result[:success]).to be(true)
        expect(result[:filepath]).to eq(filepath)
        expect(result[:size]).to eq(expected_json.bytesize)
        expect(File).to have_received(:write).with(filepath, expected_json)
      end
    end

    context 'when filepath is not provided' do
      let(:report) do
        { foo: 'bar', nums: [1, 2, 3] }
      end

      it 'returns pretty JSON data' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be(true)
        parsed = JSON.parse(result[:data])
        expect(parsed).to eq(JSON.parse(JSON.pretty_generate(report)))
      end
    end

    context 'when an error occurs during file write' do
      let(:report) do
        { x: 1 }
      end

      it 'returns an error response' do
        allow(File).to receive(:write).and_raise(StandardError.new('boom'))
        result = reporter.export_to_json(report, 'some/path.json')
        expect(result[:success]).to be(false)
        expect(result[:error]).to eq('boom')
      end
    end
  end

  describe '#compare_users' do
    let(:reporter) do
      described_class.new
    end

    context 'when fewer than 2 users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with multiple users' do
      let(:user_ids) do
        %w[u1 u2 u3]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{
                                                                                   'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'a'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{
                                                                                   'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'b'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([{
                                                                                   'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'c'
                                                                                 }])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({
                                                                                  total_actions: 10, unique_actions: 2, action_counts: { 'a' => 10 },
                                                                                  first_activity: '2023-01-01T00:00:00Z', last_activity: '2023-01-02T00:00:00Z', most_frequent: 'a'
                                                                                })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({
                                                                                  total_actions: 200, unique_actions: 3, action_counts: { 'b' => 180, 'c' => 20 },
                                                                                  first_activity: '2023-01-01T00:00:00Z', last_activity: '2023-01-03T00:00:00Z', most_frequent: 'b'
                                                                                })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({
                                                                                  total_actions: 50, unique_actions: 4, action_counts: { 'c' => 50 },
                                                                                  first_activity: '2023-01-01T00:00:00Z', last_activity: '2023-01-02T12:00:00Z', most_frequent: 'c'
                                                                                })

        allow(reporter).to receive(:fetch_user_score).with(kind_of(Array)).and_return(10.1, 99.9, 50.0)
      end

      it 'computes comparisons sorted by engagement score with top user and average score' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        comps = result[:comparisons]
        expect(comps.length).to eq(3)
        expect(comps[0][:user_id]).to eq('u2')
        expect(comps[0][:engagement_score]).to eq(99.9)
        expect(comps[0][:most_frequent_action]).to eq('b')

        expect(comps[1][:user_id]).to eq('u3')
        expect(comps[1][:engagement_score]).to eq(50.0)

        expect(comps[2][:user_id]).to eq('u1')
        expect(comps[2][:engagement_score]).to eq(10.1)

        expect(result[:top_user]).to eq('u2')
        expected_avg = ((99.9 + 50.0 + 10.1) / 3.0).round(2)
        expect(result[:average_score]).to eq(expected_avg)
      end
    end
  end
end
