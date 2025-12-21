require 'spec_helper'
require 'json'
require 'time'
require 'rails_helper'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new
  end

  let(:now) do
    Time.parse('2025-01-01T12:00:00Z')
  end

  before do
    allow(Time).to receive(:now).and_return(now)
  end

  describe '#initialize' do
    it 'sets default service URLs' do
      instance = described_class.new
      expect(instance.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
      expect(instance.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
    end

    it 'accepts custom service URLs' do
      instance = described_class.new(go_service_url: 'http://go', python_service_url: 'http://py')
      expect(instance.instance_variable_get(:@go_service_url)).to eq('http://go')
      expect(instance.instance_variable_get(:@python_service_url)).to eq('http://py')
    end
  end

  describe '#generate_report' do
    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(123).and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report(123)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(now.iso8601)
      end
    end

    context 'when activities and data are available' do
      let(:user_id) do
        123
      end

      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T09:00:00Z' },
          { 'action' => 'click', 'timestamp' => '2025-01-01T10:00:00Z' },
          { 'action' => 'logout', 'timestamp' => '2025-01-02T15:00:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 12,
          action_counts: { 'login' => 1, 'click' => 1, 'logout' => 1 },
          first_activity: '2025-01-01T09:00:00Z',
          last_activity: '2025-01-02T15:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'sequence', 'description' => 'login then click', 'confidence' => 0.9 },
          { 'pattern_type' => 'daily', 'description' => 'active mornings', 'confidence' => 0.8 },
          { 'pattern_type' => 'weekly', 'description' => 'midweek spikes', 'confidence' => 0.7 }
        ]
      end

      let(:formatted_patterns) do
        patterns.map do |p|
          {
            type: p['pattern_type'],
            description: p['description'],
            confidence: p['confidence']
          }
        end
      end

      let(:anomalies) do
        ['suspicious_login', 'odd_time']
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(80.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'returns a comprehensive report with expected fields' do
        result = reporter.generate_report(user_id, group_by: :day)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(now.iso8601)

        expect(result[:summary][:total_actions]).to eq(150)
        expect(result[:summary][:unique_actions]).to eq(12)
        expect(result[:summary][:engagement_score]).to eq(80.0)
        expect(result[:summary][:first_activity]).to eq('2025-01-01T09:00:00Z')
        expect(result[:summary][:last_activity]).to eq('2025-01-02T15:00:00Z')

        expect(result[:action_breakdown]).to eq(stats[:action_counts])
        expect(result[:patterns]).to eq(formatted_patterns)
        expect(result[:anomalies]).to eq(anomalies)

        expected_timeline = reporter.format_timeline(activities, :day)
        expect(result[:timeline]).to eq(expected_timeline)

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('Power user - high volume of activities')

        has_anomaly_message = result[:insights].any? do |msg|
          msg.include?('anomalous activities detected')
        end
        expect(has_anomaly_message).to be true
      end

      it 'defaults to day grouping when group_by is unknown' do
        result = reporter.generate_report(user_id, group_by: :unknown)
        all_day_format = result[:timeline].all? do |entry|
          entry[:period].match(/^\d{4}-\d{2}-\d{2}$/)
        end
        expect(all_day_format).to be true
      end

      it 'builds an hourly timeline when requested' do
        result = reporter.generate_report(user_id, group_by: :hour)
        periods = result[:timeline].map do |e|
          e[:period]
        end
        expect(periods).to include('2025-01-01 09:00')
        expect(periods).to include('2025-01-01 10:00')
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities are empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([], :day)).to eq([])
      end
    end

    context 'grouping by different periods' do
      let(:activities) do
        [
          { 'action' => 'a', 'timestamp' => '2025-01-01T00:30:00Z' },
          { 'action' => 'b', 'timestamp' => '2025-01-01T00:45:00Z' },
          { 'action' => 'a', 'timestamp' => '2025-01-01T13:00:00Z' },
          { 'action' => 'c', 'timestamp' => '2025-01-08T01:00:00Z' }
        ]
      end

      it 'groups by hour' do
        timeline = reporter.format_timeline(activities, :hour)
        periods = timeline.map do |e|
          e[:period]
        end
        expect(periods).to include('2025-01-01 00:00')

        first_bucket = timeline.detect do |e|
          e[:period] == '2025-01-01 00:00'
        end
        expect(first_bucket[:total_actions]).to eq(2)
        expect(first_bucket[:actions]['a']).to eq(1)
        expect(first_bucket[:actions]['b']).to eq(1)
      end

      it 'groups by day' do
        timeline = reporter.format_timeline(activities, :day)
        periods = timeline.map do |e|
          e[:period]
        end
        expect(periods).to include('2025-01-01')
        expect(periods).to include('2025-01-08')

        day_bucket = timeline.detect do |e|
          e[:period] == '2025-01-01'
        end
        expect(day_bucket[:total_actions]).to eq(3)
        expect(day_bucket[:actions]['a']).to eq(2)
        expect(day_bucket[:actions]['b']).to eq(1)
      end

      it 'groups by week (ISO week)' do
        timeline = reporter.format_timeline(activities, :week)
        periods = timeline.map do |e|
          e[:period]
        end
        expect(periods).to include('2025-W01')
        expect(periods).to include('2025-W02')
      end

      it 'groups by month' do
        timeline = reporter.format_timeline(activities, :month)
        periods = timeline.map do |e|
          e[:period]
        end
        expect(periods).to include('2025-01')
      end
    end

    context 'when timestamps are invalid' do
      let(:bad_activities) do
        [
          { 'action' => 'a', 'timestamp' => 'not a time' }
        ]
      end

      it 'falls back to current time for grouping and keeps original timestamps in entries' do
        timeline = reporter.format_timeline(bad_activities, :day)
        expect(timeline.length).to eq(1)
        expect(timeline.first[:period]).to eq(now.strftime('%Y-%m-%d'))
        expect(timeline.first[:first_timestamp]).to eq('not a time')
        expect(timeline.first[:last_timestamp]).to eq('not a time')
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      { foo: 'bar', nested: { a: 1 } }
    end

    it 'returns JSON data when no filepath is provided' do
      result = reporter.export_to_json(report)
      expect(result[:success]).to be true
      parsed = JSON.parse(result[:data])
      expect(parsed['foo']).to eq('bar')
      expect(parsed['nested']['a']).to eq(1)
    end

    it 'writes JSON data to the provided filepath' do
      require 'tmpdir'
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(report, path)
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(path)
        expect(File.exist?(path)).to be true
        content = File.read(path)
        expect(content).to include('"foo": "bar"')
        expect(result[:size]).to eq(content.bytesize)
      end
    end

    it 'returns an error object when writing fails' do
      path = '/tmp/fail.json'
      allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      result = reporter.export_to_json(report, path)
      expect(result[:success]).to be false
      expect(result[:error]).to include('disk full')
    end
  end

  describe '#compare_users' do
    context 'when fewer than 2 users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users([1])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(now.iso8601)
      end
    end

    context 'when comparing two users' do
      let(:acts1) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T00:00:00Z' }
        ]
      end

      let(:acts2) do
        [
          { 'action' => 'click', 'timestamp' => '2025-01-02T00:00:00Z' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(1).and_return(acts1)
        allow(reporter).to receive(:fetch_activity_stats).with(1).and_return({
          total_actions: 10,
          unique_actions: 2,
          action_counts: {},
          first_activity: 'a',
          last_activity: 'b',
          most_frequent: 'login'
        })
        allow(reporter).to receive(:fetch_user_score).with(acts1).and_return(70.0)

        allow(reporter).to receive(:fetch_user_activities).with(2).and_return(acts2)
        allow(reporter).to receive(:fetch_activity_stats).with(2).and_return({
          total_actions: 5,
          unique_actions: 1,
          action_counts: {},
          first_activity: 'a',
          last_activity: 'b',
          most_frequent: 'click'
        })
        allow(reporter).to receive(:fetch_user_score).with(acts2).and_return(40.0)
      end

      it 'returns sorted comparisons with top_user and average_score' do
        result = reporter.compare_users([1, 2])
        expect(result[:total_users]).to eq(2)
        ids_in_order = result[:comparisons].map do |c|
          c[:user_id]
        end
        expect(ids_in_order).to eq([1, 2])
        expect(result[:top_user]).to eq(1)
        expect(result[:average_score]).to eq(55.0)
        expect(result[:comparisons].first[:most_frequent_action]).to eq('login')
      end

      it 'handles three users and maintains descending order by engagement score' do
        acts3 = [
          { 'action' => 'pay', 'timestamp' => '2025-01-03T00:00:00Z' }
        ]
        allow(reporter).to receive(:fetch_user_activities).with(3).and_return(acts3)
        allow(reporter).to receive(:fetch_activity_stats).with(3).and_return({
          total_actions: 20,
          unique_actions: 3,
          action_counts: {},
          first_activity: 'a',
          last_activity: 'b',
          most_frequent: 'pay'
        })
        allow(reporter).to receive(:fetch_user_score).with(acts3).and_return(90.0)

        result = reporter.compare_users([1, 2, 3])
        pairs = result[:comparisons].map do |c|
          [c[:user_id], c[:engagement_score]]
        end
        expect(pairs).to eq([[3, 90.0], [1, 70.0], [2, 40.0]])
        expect(result[:top_user]).to eq(3)
        expect(result[:average_score]).to eq(((90.0 + 70.0 + 40.0) / 3.0).round(2))
      end
    end
  end
end
