require 'json'
require 'time'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  describe '#initialize' do
    context 'with default URLs' do
      let(:instance) { described_class.new }

      it 'sets default service URLs' do
        expect(instance.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
        expect(instance.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
      end
    end

    context 'with custom URLs' do
      let(:instance) { described_class.new(go_service_url: 'http://go.example.com', python_service_url: 'http://py.example.com') }

      it 'sets custom URLs' do
        expect(instance.instance_variable_get(:@go_service_url)).to eq('http://go.example.com')
        expect(instance.instance_variable_get(:@python_service_url)).to eq('http://py.example.com')
      end
    end
  end

  describe '#generate_report' do
    let(:instance) { described_class.new }
    let(:user_id) { 'user-1' }

    context 'when no activities are found' do
      before do
        allow(instance).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report' do
        result = instance.generate_report(user_id)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with activities and default grouping (day)' do
      let(:activities) do
        [
          { 'timestamp' => '2023-01-01T10:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2023-01-01T11:00:00Z', 'action' => 'click' }
        ]
      end

      let(:stats) do
        {
          total_actions: 2,
          unique_actions: 2,
          action_counts: { 'login' => 1, 'click' => 1 },
          first_activity: '2023-01-01T10:00:00Z',
          last_activity: '2023-01-01T11:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'streak', 'description' => 'daily', 'confidence' => 0.9 },
          { 'pattern_type' => 'time_of_day', 'description' => 'morning', 'confidence' => 0.7 },
          { 'pattern_type' => 'sequence', 'description' => 'login->click', 'confidence' => 0.6 }
        ]
      end

      let(:patterns_formatted) do
        patterns_raw.map do |p|
          { type: p['pattern_type'], description: p['description'], confidence: p['confidence'] }
        end
      end

      let(:score) { 80.5 }
      let(:anomalies) { ['odd'] }
      let(:timeline) do
        [
          {
            period: '2023-01-01',
            total_actions: 2,
            actions: { 'login' => 1, 'click' => 1 },
            first_timestamp: '2023-01-01T10:00:00Z',
            last_timestamp: '2023-01-01T11:00:00Z'
          }
        ]
      end

      before do
        allow(instance).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(instance).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(instance).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(instance).to receive(:fetch_user_score).with(activities).and_return(score)
        allow(instance).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
        expect(instance).to receive(:format_timeline).with(activities, :day).and_return(timeline)
      end

      it 'returns a complete report with insights and mapped patterns' do
        result = instance.generate_report(user_id)
        expect(result[:user_id]).to eq(user_id)
        expect(result[:summary]).to include(
          total_actions: 2,
          unique_actions: 2,
          engagement_score: score,
          first_activity: '2023-01-01T10:00:00Z',
          last_activity: '2023-01-01T11:00:00Z'
        )
        expect(result[:action_breakdown]).to eq(stats[:action_counts])
        expect(result[:patterns]).to eq(patterns_formatted)
        expect(result[:anomalies]).to eq(anomalies)
        expect(result[:timeline]).to eq(timeline)
        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
      end
    end

    context 'with custom group_by option (:hour) and low engagement' do
      let(:activities) do
        [
          { 'timestamp' => '2023-01-01T10:00:00Z', 'action' => 'login' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 11,
          action_counts: { 'login' => 1 },
          first_activity: '2023-01-01T10:00:00Z',
          last_activity: '2023-01-01T10:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:score) { 40.0 }

      before do
        allow(instance).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(instance).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(instance).to receive(:fetch_activity_patterns).with(activities).and_return([])
        allow(instance).to receive(:fetch_user_score).with(activities).and_return(score)
        allow(instance).to receive(:fetch_anomalies).with(activities).and_return([])
        expect(instance).to receive(:format_timeline).with(activities, :hour).and_return([])
      end

      it 'uses the specified grouping and includes appropriate insights' do
        result = instance.generate_report(user_id, group_by: :hour)
        expect(result[:timeline]).to eq([])
        expect(result[:insights]).to include('Low engagement - consider re-engagement strategies')
        expect(result[:insights]).to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#format_timeline' do
    let(:instance) { described_class.new }

    let(:activities) do
      [
        { 'timestamp' => '2023-01-01T08:15:00Z', 'action' => 'login' },
        { 'timestamp' => '2023-01-01T08:30:00Z', 'action' => 'click' },
        { 'timestamp' => '2023-01-01T09:05:00Z', 'action' => 'click' },
        { 'timestamp' => '2023-01-02T10:00:00Z', 'action' => 'logout' }
      ]
    end

    it 'returns empty array for empty activities' do
      expect(instance.format_timeline([], :day)).to eq([])
    end

    context 'when grouping by day' do
      it 'groups activities per day with action counts and timestamps' do
        result = instance.format_timeline(activities, :day)
        expect(result.length).to eq(2)
        first_day = result.find do |e|
          e[:period] == '2023-01-01'
        end
        expect(first_day[:total_actions]).to eq(3)
        expect(first_day[:actions]).to eq({ 'login' => 1, 'click' => 2 })
        expect(first_day[:first_timestamp]).to eq('2023-01-01T08:15:00Z')
        expect(first_day[:last_timestamp]).to eq('2023-01-01T09:05:00Z')
        second_day = result.find do |e|
          e[:period] == '2023-01-02'
        end
        expect(second_day[:total_actions]).to eq(1)
        expect(second_day[:actions]).to eq({ 'logout' => 1 })
      end
    end

    context 'when grouping by hour' do
      it 'groups activities by hour with formatted period' do
        result = instance.format_timeline(activities, :hour)
        expect(result.any? do |e|
          e[:period] == '2023-01-01 08:00'
        end).to be true
        hour8 = result.find do |e|
          e[:period] == '2023-01-01 08:00'
        end
        expect(hour8[:total_actions]).to eq(2)
        expect(hour8[:actions]).to eq({ 'login' => 1, 'click' => 1 })
      end
    end

    context 'when grouping by week' do
      it 'groups activities into ISO week buckets' do
        result = instance.format_timeline(activities, :week)
        expect(result.first[:period]).to match(/\A\d{4}-W\d{2}\z/)
      end
    end

    context 'when grouping by month' do
      it 'groups activities into month buckets' do
        result = instance.format_timeline(activities, :month)
        expect(result.any? do |e|
          e[:period] == '2023-01'
        end).to be true
      end
    end

    context 'when group_by is unknown' do
      it 'defaults to day grouping' do
        result = instance.format_timeline(activities, :unknown)
        periods = result.map do |e|
          e[:period]
        end
        expect(periods).to include('2023-01-01')
        expect(periods).to include('2023-01-02')
      end
    end

    context 'when an activity has invalid timestamp' do
      it 'uses current time for grouping' do
        fixed_time = Time.new(2023, 1, 3, 12, 0, 0, '+00:00')
        allow(Time).to receive(:now).and_return(fixed_time)
        acts = [{ 'timestamp' => 'not-a-time', 'action' => 'login' }]
        result = instance.format_timeline(acts, :day)
        expect(result.length).to eq(1)
        expect(result.first[:period]).to eq('2023-01-03')
      end
    end
  end

  describe '#export_to_json' do
    let(:instance) { described_class.new }
    let(:report) { { a: 1, b: [1, 2] } }

    context 'when a filepath is provided' do
      it 'writes pretty JSON to file and returns metadata' do
        path = '/tmp/report.json'
        expect(File).to receive(:write) do |fp, data|
          expect(fp).to eq(path)
          parsed = JSON.parse(data)
          expect(parsed).to eq(JSON.parse(JSON.pretty_generate(report)))
        end
        result = instance.export_to_json(report, path)
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(path)
        expect(result[:size]).to be > 0
      end
    end

    context 'when no filepath is provided' do
      it 'returns pretty JSON data' do
        result = instance.export_to_json(report)
        expect(result[:success]).to be true
        expect(result[:data]).to be_a(String)
        expect(JSON.parse(result[:data])).to eq(JSON.parse(JSON.pretty_generate(report)))
      end
    end

    context 'when file writing fails' do
      it 'returns an error response' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        result = instance.export_to_json(report, '/tmp/report.json')
        expect(result[:success]).to be false
        expect(result[:error]).to include('disk full')
      end
    end
  end

  describe '#compare_users' do
    let(:instance) { described_class.new }

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = instance.compare_users([1])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'when multiple users are compared' do
      it 'returns sorted comparisons, top user, and average score' do
        allow(instance).to receive(:fetch_user_activities).with(1).and_return([{ 'timestamp' => '2023-01-01T00:00:00Z',
                                                                                 'action' => 'a' }])
        allow(instance).to receive(:fetch_user_activities).with(2).and_return([{ 'timestamp' => '2023-01-01T00:00:00Z',
                                                                                 'action' => 'b' }])
        allow(instance).to receive(:fetch_activity_stats).with(1).and_return({ total_actions: 10, unique_actions: 2,
                                                                               action_counts: {}, first_activity: 'f', last_activity: 'l', most_frequent: 'a' })
        allow(instance).to receive(:fetch_activity_stats).with(2).and_return({ total_actions: 20, unique_actions: 3,
                                                                               action_counts: {}, first_activity: 'f', last_activity: 'l', most_frequent: 'b' })
        allow(instance).to receive(:fetch_user_score).with([{ 'timestamp' => '2023-01-01T00:00:00Z',
                                                              'action' => 'a' }]).and_return(55.0)
        allow(instance).to receive(:fetch_user_score).with([{ 'timestamp' => '2023-01-01T00:00:00Z',
                                                              'action' => 'b' }]).and_return(70.0)

        result = instance.compare_users([1, 2])

        expect(result[:total_users]).to eq(2)
        user_ids_sorted = result[:comparisons].map do |c|
          c[:user_id]
        end
        expect(user_ids_sorted).to eq([2, 1])
        expect(result[:comparisons].first).to include(user_id: 2, total_actions: 20, engagement_score: 70.0,
                                                      most_frequent_action: 'b')
        expect(result[:top_user]).to eq(2)
        expect(result[:average_score]).to eq(((55.0 + 70.0) / 2.0).round(2))
      end
    end

    context 'when users have equal engagement scores' do
      it 'keeps insertion order for ties' do
        allow(instance).to receive(:fetch_user_activities).with('a').and_return([{
                                                                                  'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'x'
                                                                                }])
        allow(instance).to receive(:fetch_user_activities).with('b').and_return([{
                                                                                  'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'y'
                                                                                }])
        allow(instance).to receive(:fetch_activity_stats).with('a').and_return({ total_actions: 5, unique_actions: 1,
                                                                                 action_counts: {}, first_activity: 'f', last_activity: 'l', most_frequent: 'x' })
        allow(instance).to receive(:fetch_activity_stats).with('b').and_return({ total_actions: 6, unique_actions: 1,
                                                                                 action_counts: {}, first_activity: 'f', last_activity: 'l', most_frequent: 'y' })
        allow(instance).to receive(:fetch_user_score).with([{ 'timestamp' => '2023-01-01T00:00:00Z',
                                                              'action' => 'x' }]).and_return(42.0)
        allow(instance).to receive(:fetch_user_score).with([{ 'timestamp' => '2023-01-01T00:00:00Z',
                                                              'action' => 'y' }]).and_return(42.0)

        result = instance.compare_users(%w[a b])
        user_ids_sorted = result[:comparisons].map do |c|
          c[:user_id]
        end
        expect(user_ids_sorted).to eq(%w[a b])
      end
    end
  end
end
