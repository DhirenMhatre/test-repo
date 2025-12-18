require 'spec_helper'
require 'json'
require 'time'
require 'tmpdir'
require 'rails_helper'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new(
      go_service_url: 'http://localhost:8080',
      python_service_url: 'http://localhost:8081'
    )
  end

  describe '#generate_report' do
    let(:user_id) { 'user-123' }

    context 'when no activities are found' do
      it 'returns an error report with message "No activities found"' do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
        fixed_now = Time.parse('2024-01-10T12:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_now)

        result = reporter.generate_report(user_id)

        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_now.iso8601)
      end
    end

    context 'when activities exist' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-01T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2024-01-02T12:00:00Z', 'action' => 'logout' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 3,
          action_counts: { 'login' => 1, 'click' => 1, 'logout' => 1 },
          first_activity: '2024-01-01T10:15:00Z',
          last_activity: '2024-01-02T12:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'daily_peak', 'description' => 'Peak at 11am', 'confidence' => 0.9 },
          { 'pattern_type' => 'weekly_rhythm', 'description' => 'Active Mondays', 'confidence' => 0.8 }
        ]
      end

      let(:user_score) { 80.5 }
      let(:anomalies) { ['suspicious login'] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
        allow(Time).to receive(:now).and_return(Time.parse('2024-01-03T00:00:00Z'))
      end

      it 'builds a comprehensive report with timeline grouped by default day' do
        result = reporter.generate_report(user_id)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq('2024-01-03T00:00:00Z')

        expect(result[:summary][:total_actions]).to eq(3)
        expect(result[:summary][:unique_actions]).to eq(3)
        expect(result[:summary][:engagement_score]).to eq(80.5)
        expect(result[:summary][:first_activity]).to eq('2024-01-01T10:15:00Z')
        expect(result[:summary][:last_activity]).to eq('2024-01-02T12:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'login' => 1, 'click' => 1, 'logout' => 1 })

        expect(result[:patterns]).to eq([
                                          { type: 'daily_peak', description: 'Peak at 11am', confidence: 0.9 },
                                          { type: 'weekly_rhythm', description: 'Active Mondays', confidence: 0.8 }
                                        ])

        expect(result[:anomalies]).to eq(['suspicious login'])

        expect(result[:timeline].map { |e| e[:period] }).to eq(%w[2024-01-01 2024-01-02])
        first_day = result[:timeline][0]
        expect(first_day[:total_actions]).to eq(2)
        expect(first_day[:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(first_day[:first_timestamp]).to eq('2024-01-01T10:15:00Z')
        expect(first_day[:last_timestamp]).to eq('2024-01-01T11:00:00Z')

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(result[:insights].any? { |i| i.include?('Power user') }).to be false
      end

      it 'respects group_by option for timeline when set to :month' do
        result = reporter.generate_report(user_id, group_by: :month)
        expect(result[:timeline].map { |e| e[:period] }).to eq(['2024-01'])
        expect(result[:timeline].first[:total_actions]).to eq(3)
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities array is empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([], :day)).to eq([])
      end
    end

    context 'when grouping by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-01T10:05:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-01-01T10:30:00Z', 'action' => 'click' },
          { 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2024-01-08T09:00:00Z', 'action' => 'logout' }
        ]
      end

      it 'groups activities per hour and counts actions correctly' do
        result = reporter.format_timeline(activities, :hour)
        expect(result.map { |e| e[:period] }).to eq(['2024-01-01 10:00', '2024-01-01 11:00', '2024-01-08 09:00'])

        hour_10 = result[0]
        expect(hour_10[:total_actions]).to eq(2)
        expect(hour_10[:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(hour_10[:first_timestamp]).to eq('2024-01-01T10:05:00Z')
        expect(hour_10[:last_timestamp]).to eq('2024-01-01T10:30:00Z')

        hour_11 = result[1]
        expect(hour_11[:total_actions]).to eq(1)
        expect(hour_11[:actions]).to eq({ 'click' => 1 })

        hour_0900 = result[2]
        expect(hour_0900[:total_actions]).to eq(1)
        expect(hour_0900[:actions]).to eq({ 'logout' => 1 })
      end
    end

    context 'when grouping by day' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-01T10:05:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-01-01T10:30:00Z', 'action' => 'click' },
          { 'timestamp' => '2024-01-08T09:00:00Z', 'action' => 'logout' }
        ]
      end

      it 'groups by day and sorts periods ascending' do
        result = reporter.format_timeline(activities, :day)
        expect(result.map { |e| e[:period] }).to eq(%w[2024-01-01 2024-01-08])
        expect(result[0][:total_actions]).to eq(2)
        expect(result[1][:total_actions]).to eq(1)
      end
    end

    context 'when grouping by week' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-01T10:05:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-01-08T09:00:00Z', 'action' => 'logout' }
        ]
      end

      it 'uses ISO week format YYYY-W##' do
        result = reporter.format_timeline(activities, :week)
        expect(result.map { |e| e[:period] }).to eq(%w[2024-W01 2024-W02])
      end
    end

    context 'when grouping by month' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-01T10:05:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-01-15T09:00:00Z', 'action' => 'logout' }
        ]
      end

      it 'groups by month' do
        result = reporter.format_timeline(activities, :month)
        expect(result.map { |e| e[:period] }).to eq(['2024-01'])
        expect(result.first[:total_actions]).to eq(2)
        expect(result.first[:actions]).to eq({ 'login' => 1, 'logout' => 1 })
      end
    end

    context 'when an unknown group_by is provided' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-01T10:05:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-01-01T10:30:00Z', 'action' => 'click' }
        ]
      end

      it 'falls back to day grouping' do
        result = reporter.format_timeline(activities, :unknown)
        expect(result.map { |e| e[:period] }).to eq(['2024-01-01'])
        expect(result.first[:actions]).to eq({ 'login' => 1, 'click' => 1 })
      end
    end

    context 'when timestamp is invalid' do
      let(:activities) do
        [
          { 'timestamp' => 'not-a-time', 'action' => 'click' }
        ]
      end

      it 'uses Time.now as fallback for period assignment' do
        fixed_now = Time.parse('2024-06-15T12:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_now)
        result = reporter.format_timeline(activities, :day)
        expect(result.map { |e| e[:period] }).to eq(['2024-06-15'])
        expect(result.first[:actions]).to eq({ 'click' => 1 })
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 'user-1',
        summary: {
          total_actions: 2,
          unique_actions: 2
        }
      }
    end

    it 'returns success and JSON data when filepath is not provided' do
      result = reporter.export_to_json(report)
      expected_json = JSON.pretty_generate(report)
      expect(result[:success]).to be true
      expect(result[:data]).to eq(expected_json)
    end

    it 'writes to file and returns success with filepath and size when filepath provided' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(report, path)
        expected_json = JSON.pretty_generate(report)
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(path)
        expect(result[:size]).to eq(expected_json.bytesize)
        file_contents = File.read(path)
        expect(file_contents).to eq(expected_json)
      end
    end

    it 'returns an error when file write raises an exception' do
      allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      result = reporter.export_to_json(report, '/some/path/report.json')
      expect(result[:success]).to be false
      expect(result[:error]).to eq('disk full')
    end
  end

  describe '#compare_users' do
    context 'when less than two users are provided' do
      it 'returns an error report' do
        fixed_now = Time.parse('2024-01-10T12:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_now)
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_now.iso8601)
      end
    end

    context 'with three users having different engagement scores' do
      let(:user_ids) { [1, 2, 3] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(1).and_return([{ 'timestamp' => 't1' }])
        allow(reporter).to receive(:fetch_user_activities).with(2).and_return([{ 'timestamp' => 't2' }])
        allow(reporter).to receive(:fetch_user_activities).with(3).and_return([{ 'timestamp' => 't3' }])

        allow(reporter).to receive(:fetch_activity_stats).with(1).and_return({
                                                                               total_actions: 10, unique_actions: 3, action_counts: {}, first_activity: 't1', last_activity: 't1', most_frequent: 'click'
                                                                             })
        allow(reporter).to receive(:fetch_activity_stats).with(2).and_return({
                                                                               total_actions: 20, unique_actions: 5, action_counts: {}, first_activity: 't2', last_activity: 't2', most_frequent: 'view'
                                                                             })
        allow(reporter).to receive(:fetch_activity_stats).with(3).and_return({
                                                                               total_actions: 5, unique_actions: 2, action_counts: {}, first_activity: 't3', last_activity: 't3', most_frequent: 'login'
                                                                             })

        allow(reporter).to receive(:fetch_user_score).and_return(60, 80, 40)
      end

      it 'returns sorted comparisons and correct top_user and average_score' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:top_user]).to eq(2)
        expect(result[:average_score]).to eq(60.0)

        comparisons = result[:comparisons]
        expect(comparisons.map { |c| c[:user_id] }).to eq([2, 1, 3])

        user2 = comparisons[0]
        expect(user2[:user_id]).to eq(2)
        expect(user2[:engagement_score]).to eq(80)
        expect(user2[:total_actions]).to eq(20)
        expect(user2[:most_frequent_action]).to eq('view')

        user1 = comparisons[1]
        expect(user1[:user_id]).to eq(1)
        expect(user1[:engagement_score]).to eq(60)
        expect(user1[:total_actions]).to eq(10)
        expect(user1[:most_frequent_action]).to eq('click')

        user3 = comparisons[2]
        expect(user3[:user_id]).to eq(3)
        expect(user3[:engagement_score]).to eq(40)
        expect(user3[:total_actions]).to eq(5)
        expect(user3[:most_frequent_action]).to eq('login')
      end
    end

    context 'when users have equal engagement scores' do
      let(:user_ids) { %i[a b] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(:a).and_return([{ 'timestamp' => 't1' }])
        allow(reporter).to receive(:fetch_user_activities).with(:b).and_return([{ 'timestamp' => 't2' }])

        allow(reporter).to receive(:fetch_activity_stats).with(:a).and_return({
                                                                                total_actions: 7, unique_actions: 3, action_counts: {}, first_activity: 't1', last_activity: 't1', most_frequent: 'click'
                                                                              })
        allow(reporter).to receive(:fetch_activity_stats).with(:b).and_return({
                                                                                total_actions: 9, unique_actions: 4, action_counts: {}, first_activity: 't2', last_activity: 't2', most_frequent: 'view'
                                                                              })

        allow(reporter).to receive(:fetch_user_score).and_return(50, 50)
      end

      it 'keeps the original order when scores are equal' do
        result = reporter.compare_users(user_ids)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%i[a b])
        expect(result[:top_user]).to eq(:a)
        expect(result[:average_score]).to eq(50.0)
      end
    end
  end
end
