require 'spec_helper'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  describe '#generate_report' do
    let(:reporter) do
      described_class.new(go_service_url: 'http://go', python_service_url: 'http://py')
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(123).and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report(123)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with activities and options' do
      let(:user_id) { 42 }
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2023-01-01T10:15:00Z' },
          { 'action' => 'click', 'timestamp' => '2023-01-01T12:00:00Z' },
          { 'action' => 'logout', 'timestamp' => '2023-01-02T09:00:00Z' }
        ]
      end
      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 11,
          action_counts: { 'login' => 1, 'click' => 2, 'logout' => 1 },
          first_activity: '2023-01-01T10:15:00Z',
          last_activity: '2023-01-02T09:00:00Z',
          most_frequent: 'click'
        }
      end
      let(:patterns) do
        [
          { 'pattern_type' => 'spike', 'description' => 'Morning spikes', 'confidence' => 0.9 },
          { 'pattern_type' => 'habit', 'description' => 'Daily login', 'confidence' => 0.8 },
          { 'pattern_type' => 'sequence', 'description' => 'Login->click', 'confidence' => 0.7 }
        ]
      end
      let(:user_score) { 82.5 }
      let(:anomalies) { ['suspicious-ip'] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a report including summary, breakdown, patterns, anomalies, timeline, and insights' do
        report = reporter.generate_report(user_id, group_by: :day)

        expect(report[:user_id]).to eq(user_id)
        expect(report[:generated_at]).to be_a(String)

        expect(report[:summary][:total_actions]).to eq(150)
        expect(report[:summary][:unique_actions]).to eq(11)
        expect(report[:summary][:engagement_score]).to eq(user_score)
        expect(report[:summary][:first_activity]).to eq(stats[:first_activity])
        expect(report[:summary][:last_activity]).to eq(stats[:last_activity])

        expect(report[:action_breakdown]).to eq(stats[:action_counts])

        expected_patterns = [
          { type: 'spike', description: 'Morning spikes', confidence: 0.9 },
          { type: 'habit', description: 'Daily login', confidence: 0.8 },
          { type: 'sequence', description: 'Login->click', confidence: 0.7 }
        ]
        expect(report[:patterns]).to eq(expected_patterns)

        expect(report[:anomalies]).to eq(anomalies)

        expect(report[:timeline]).to be_an(Array)
        expect(report[:timeline].map { |t| t[:period] }).to eq(%w[2023-01-01 2023-01-02])
        day1 = report[:timeline].find { |t| t[:period] == '2023-01-01' }
        day2 = report[:timeline].find { |t| t[:period] == '2023-01-02' }

        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(day1[:first_timestamp]).to eq('2023-01-01T10:15:00Z')
        expect(day1[:last_timestamp]).to eq('2023-01-01T12:00:00Z')

        expect(day2[:total_actions]).to eq(1)
        expect(day2[:actions]).to eq({ 'logout' => 1 })
        expect(day2[:first_timestamp]).to eq('2023-01-02T09:00:00Z')
        expect(day2[:last_timestamp]).to eq('2023-01-02T09:00:00Z')

        expect(report[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(report[:insights]).to include('Diverse activity profile across multiple action types')
        expect(report[:insights]).to include('Clear behavioral patterns detected')
        expect(report[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(report[:insights]).to include('Power user - high volume of activities')
      end
    end

    context 'with low engagement and minimal variation' do
      let(:user_id) { 7 }
      let(:activities) do
        [
          { 'action' => 'view', 'timestamp' => '2023-02-01T10:00:00Z' },
          { 'action' => 'view', 'timestamp' => '2023-02-01T11:00:00Z' }
        ]
      end
      let(:stats) do
        {
          total_actions: 5,
          unique_actions: 2,
          action_counts: { 'view' => 5 },
          first_activity: '2023-02-01T10:00:00Z',
          last_activity: '2023-02-01T12:00:00Z',
          most_frequent: 'view'
        }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return([])
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(40.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([])
      end

      it 'provides low engagement insight only' do
        report = reporter.generate_report(user_id)
        expect(report[:insights]).to include('Low engagement - consider re-engagement strategies')
        expect(report[:insights].any? { |i| i.include?('Highly engaged') }).to be false
        expect(report[:insights].any? { |i| i.include?('Moderately engaged') }).to be false
        expect(report[:insights].any? { |i| i.include?('Diverse activity') }).to be false
        expect(report[:insights].any? { |i| i.include?('Power user') }).to be false
        expect(report[:insights].any? { |i| i.include?('anomalous') }).to be false
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) { described_class.new }

    context 'when activities array is empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([], :day)).to eq([])
      end
    end

    context 'groups by hour with valid and invalid timestamps' do
      let(:activities) do
        [
          { 'action' => 'a1', 'timestamp' => '2023-01-01T10:15:00Z' },
          { 'action' => 'a2', 'timestamp' => '2023-01-01T10:45:00Z' },
          { 'action' => 'a1', 'timestamp' => '2023-01-01T11:00:00Z' },
          { 'action' => 'a2', 'timestamp' => 'invalid' }
        ]
      end

      before do
        allow(reporter).to receive(:parse_timestamp).and_call_original
        allow(reporter).to receive(:parse_timestamp).with('invalid').and_return(Time.parse('2023-01-01T11:30:00Z'))
      end

      it 'buckets activities into hourly periods and sorts by period' do
        timeline = reporter.format_timeline(activities, :hour)
        expect(timeline.map { |t| t[:period] }).to eq(['2023-01-01 10:00', '2023-01-01 11:00'])

        hour10 = timeline[0]
        hour11 = timeline[1]

        expect(hour10[:total_actions]).to eq(2)
        expect(hour10[:actions]).to eq({ 'a1' => 1, 'a2' => 1 })
        expect(hour10[:first_timestamp]).to eq('2023-01-01T10:15:00Z')
        expect(hour10[:last_timestamp]).to eq('2023-01-01T10:45:00Z')

        expect(hour11[:total_actions]).to eq(2)
        expect(hour11[:actions]).to eq({ 'a1' => 1, 'a2' => 1 })
        expect(hour11[:first_timestamp]).to eq('2023-01-01T11:00:00Z')
        expect(hour11[:last_timestamp]).to eq('invalid')
      end
    end

    context 'groups by day across multiple days' do
      let(:activities) do
        [
          { 'action' => 'x', 'timestamp' => '2023-03-01T00:00:00Z' },
          { 'action' => 'y', 'timestamp' => '2023-03-02T23:59:59Z' }
        ]
      end

      it 'creates one entry per day' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.map { |t| t[:period] }).to eq(%w[2023-03-01 2023-03-02])
        expect(timeline[0][:total_actions]).to eq(1)
        expect(timeline[1][:total_actions]).to eq(1)
      end
    end

    context 'groups by week' do
      let(:activities) do
        [
          { 'action' => 'w1', 'timestamp' => '2020-01-01T12:00:00Z' },
          { 'action' => 'w2', 'timestamp' => '2020-01-08T12:00:00Z' }
        ]
      end

      it 'creates ISO week buckets' do
        timeline = reporter.format_timeline(activities, :week)
        expect(timeline.map { |t| t[:period] }).to eq(%w[2020-W01 2020-W02])
      end
    end

    context 'groups by month' do
      let(:activities) do
        [
          { 'action' => 'm1', 'timestamp' => '2020-01-15T00:00:00Z' },
          { 'action' => 'm2', 'timestamp' => '2020-02-01T00:00:00Z' }
        ]
      end

      it 'creates monthly buckets' do
        timeline = reporter.format_timeline(activities, :month)
        expect(timeline.map { |t| t[:period] }).to eq(%w[2020-01 2020-02])
      end
    end
  end

  describe '#export_to_json' do
    let(:reporter) do
      described_class.new
    end

    context 'when no filepath is provided' do
      let(:report) { { a: 1, b: 'two', c: [3, 4] } }

      it 'returns pretty JSON data' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be true
        expect(result[:data]).to be_a(String)
        parsed = JSON.parse(result[:data])
        expect(parsed).to eq(JSON.parse(JSON.pretty_generate(report)))
      end
    end

    context 'when a filepath is provided' do
      let(:report) { { foo: 'bar' } }

      it 'writes the file and returns metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(path)
          expected = JSON.pretty_generate(report)
          expect(result[:size]).to eq(expected.bytesize)
          contents = File.read(path)
          expect(contents).to eq(expected)
        end
      end
    end

    context 'when writing fails' do
      let(:report) { { error: 'x' } }

      it 'returns an error hash' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        result = reporter.export_to_json(report, '/path/that/fails.json')
        expect(result[:success]).to be false
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    let(:reporter) { described_class.new }

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users([1])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with multiple users and varying engagement scores' do
      let(:user_ids) { [1, 2, 3] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(1).and_return([{ 'action' => 'a' }])
        allow(reporter).to receive(:fetch_user_activities).with(2).and_return([{ 'action' => 'b' },
                                                                               { 'action' => 'b' }])
        allow(reporter).to receive(:fetch_user_activities).with(3).and_return([{ 'action' => 'c' }])

        allow(reporter).to receive(:fetch_activity_stats).with(1).and_return({ total_actions: 10, unique_actions: 2,
                                                                               action_counts: { 'a' => 10 }, first_activity: 't1', last_activity: 't2', most_frequent: 'a' })
        allow(reporter).to receive(:fetch_activity_stats).with(2).and_return({ total_actions: 30, unique_actions: 3,
                                                                               action_counts: { 'b' => 30 }, first_activity: 't1', last_activity: 't2', most_frequent: 'b' })
        allow(reporter).to receive(:fetch_activity_stats).with(3).and_return({ total_actions: 20, unique_actions: 1,
                                                                               action_counts: { 'c' => 20 }, first_activity: 't1', last_activity: 't2', most_frequent: 'c' })

        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'a' }]).and_return(10.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'b' }, { 'action' => 'b' }]).and_return(30.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'c' }]).and_return(20.0)
      end

      it 'returns users sorted by engagement score with summary stats' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons]).to be_an(Array)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq([2, 3, 1])

        top = result[:comparisons].first
        expect(top[:user_id]).to eq(2)
        expect(top[:engagement_score]).to eq(30.0)
        expect(top[:most_frequent_action]).to eq('b')

        expect(result[:top_user]).to eq(2)
        expect(result[:average_score]).to eq(20.0)
      end
    end
  end
end
