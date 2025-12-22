require 'spec_helper'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:go_service_url) { 'http://go.test:8080' }
  let(:python_service_url) { 'http://py.test:8081' }
  let(:reporter) do
    described_class.new(go_service_url: go_service_url, python_service_url: python_service_url)
  end

  describe '#initialize' do
    it 'stores the provided service URLs' do
      instance = described_class.new(go_service_url: go_service_url, python_service_url: python_service_url)

      expect(instance.instance_variable_get(:@go_service_url)).to eq(go_service_url)
      expect(instance.instance_variable_get(:@python_service_url)).to eq(python_service_url)
    end

    it 'uses default URLs when none are provided' do
      instance = described_class.new

      expect(instance.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
      expect(instance.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
    end
  end

  describe '#generate_report' do
    let(:user_id) { 'user-123' }

    let(:activities) do
      [
        { 'timestamp' => '2025-01-01T10:05:00Z', 'action' => 'login' },
        { 'timestamp' => '2025-01-01T11:15:00Z', 'action' => 'view' },
        { 'timestamp' => '2025-01-02T12:25:00Z', 'action' => 'login' }
      ]
    end

    let(:stats) do
      {
        total_actions: 3,
        unique_actions: 2,
        action_counts: { 'login' => 2, 'view' => 1 },
        first_activity: '2025-01-01T10:05:00Z',
        last_activity: '2025-01-02T12:25:00Z',
        most_frequent: 'login'
      }
    end

    let(:patterns) do
      [
        { 'pattern_type' => 'recurring', 'description' => 'Logs in daily', 'confidence' => 0.9 },
        { 'pattern_type' => 'time_of_day', 'description' => 'Morning usage', 'confidence' => 0.7 }
      ]
    end

    let(:anomalies) do
      [
        { 'timestamp' => '2025-01-02T03:00:00Z', 'action' => 'login', 'reason' => 'unusual time' }
      ]
    end

    let(:user_score) { 82.25 }

    context 'when no activities are found' do
      it 'returns an error report with a message and generated_at' do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
        fixed_time = Time.utc(2025, 1, 3, 0, 0, 0)
        allow(Time).to receive(:now).and_return(fixed_time)

        report = reporter.generate_report(user_id)

        expect(report[:error]).to eq(true)
        expect(report[:message]).to eq('No activities found')
        expect(report[:generated_at]).to eq(fixed_time.iso8601)
      end

      it 'does not call downstream fetch methods' do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])

        expect(reporter).not_to receive(:fetch_activity_stats)
        expect(reporter).not_to receive(:fetch_activity_patterns)
        expect(reporter).not_to receive(:fetch_user_score)
        expect(reporter).not_to receive(:fetch_anomalies)

        reporter.generate_report(user_id)
      end
    end

    context 'when activities exist' do
      it 'builds a report with expected top-level keys and values' do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)

        fixed_time = Time.utc(2025, 1, 3, 12, 34, 56)
        allow(Time).to receive(:now).and_return(fixed_time)

        report = reporter.generate_report(user_id)

        expect(report[:user_id]).to eq(user_id)
        expect(report[:generated_at]).to eq(fixed_time.iso8601)
        expect(report[:summary]).to eq(
          {
            total_actions: 3,
            unique_actions: 2,
            engagement_score: user_score,
            first_activity: stats[:first_activity],
            last_activity: stats[:last_activity]
          }
        )
        expect(report[:action_breakdown]).to eq(stats[:action_counts])
        expect(report[:anomalies]).to eq(anomalies)

        expect(report[:patterns]).to eq(
          [
            { type: 'recurring', description: 'Logs in daily', confidence: 0.9 },
            { type: 'time_of_day', description: 'Morning usage', confidence: 0.7 }
          ]
        )
      end

      it 'uses :day as default group_by for timeline when not provided' do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)

        report = reporter.generate_report(user_id)

        periods = report[:timeline].map do |e|
          e[:period]
        end

        expect(periods).to include('2025-01-01', '2025-01-02')
      end

      it 'honors provided group_by option for timeline' do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)

        report = reporter.generate_report(user_id, group_by: :month)

        periods = report[:timeline].map do |e|
          e[:period]
        end

        expect(periods).to eq(['2025-01'])
      end

      it 'includes insights generated from inputs' do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats.merge(unique_actions: 11,
                                                                                               total_actions: 101))
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns + [{
          'pattern_type' => 'sequence', 'description' => 'login->view', 'confidence' => 0.6
        }])
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(80.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)

        report = reporter.generate_report(user_id)

        expect(report[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(report[:insights]).to include('Diverse activity profile across multiple action types')
        expect(report[:insights]).to include('Clear behavioral patterns detected')
        expect(report[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(report[:insights]).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities is empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([], :day)).to eq([])
      end
    end

    context 'when grouping by hour' do
      it 'groups activities into hourly periods and sorts by period' do
        activities = [
          { 'timestamp' => '2025-01-01T10:05:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T10:45:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T09:15:00Z', 'action' => 'view' }
        ]

        timeline = reporter.format_timeline(activities, :hour)

        expect(timeline.map do |e|
          e[:period]
        end).to eq(['2025-01-01 09:00', '2025-01-01 10:00'])

        entry_9 = timeline[0]
        entry_10 = timeline[1]

        expect(entry_9[:total_actions]).to eq(1)
        expect(entry_9[:actions]).to eq({ 'view' => 1 })
        expect(entry_9[:first_timestamp]).to eq('2025-01-01T09:15:00Z')
        expect(entry_9[:last_timestamp]).to eq('2025-01-01T09:15:00Z')

        expect(entry_10[:total_actions]).to eq(2)
        expect(entry_10[:actions]).to eq({ 'login' => 2 })
        expect(entry_10[:first_timestamp]).to eq('2025-01-01T10:05:00Z')
        expect(entry_10[:last_timestamp]).to eq('2025-01-01T10:45:00Z')
      end
    end

    context 'when grouping by day' do
      it 'groups activities by date' do
        activities = [
          { 'timestamp' => '2025-01-01T10:05:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T11:15:00Z', 'action' => 'view' },
          { 'timestamp' => '2025-01-02T12:25:00Z', 'action' => 'login' }
        ]

        timeline = reporter.format_timeline(activities, :day)

        expect(timeline.length).to eq(2)
        expect(timeline[0][:period]).to eq('2025-01-01')
        expect(timeline[0][:total_actions]).to eq(2)
        expect(timeline[0][:actions]).to eq({ 'login' => 1, 'view' => 1 })

        expect(timeline[1][:period]).to eq('2025-01-02')
        expect(timeline[1][:total_actions]).to eq(1)
        expect(timeline[1][:actions]).to eq({ 'login' => 1 })
      end
    end

    context 'when grouping by week' do
      it 'groups activities by ISO week' do
        activities = [
          { 'timestamp' => '2025-01-01T10:05:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-02T12:25:00Z', 'action' => 'login' }
        ]

        timeline = reporter.format_timeline(activities, :week)

        expect(timeline.length).to eq(1)
        expect(timeline[0][:period]).to match(/\A2025-W\d{2}\z/)
        expect(timeline[0][:total_actions]).to eq(2)
        expect(timeline[0][:actions]).to eq({ 'login' => 2 })
      end
    end

    context 'when grouping by month' do
      it 'groups activities by year-month' do
        activities = [
          { 'timestamp' => '2025-01-31T23:59:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-02-01T00:00:00Z', 'action' => 'view' }
        ]

        timeline = reporter.format_timeline(activities, :month)

        expect(timeline.map do |e|
          e[:period]
        end).to eq(%w[2025-01 2025-02])
      end
    end

    context 'when an unknown group_by is provided' do
      it 'defaults to day format' do
        activities = [
          { 'timestamp' => '2025-01-01T10:05:00Z', 'action' => 'login' }
        ]

        timeline = reporter.format_timeline(activities, :unknown)

        expect(timeline.length).to eq(1)
        expect(timeline[0][:period]).to eq('2025-01-01')
      end
    end

    context 'when timestamps are invalid' do
      it 'uses Time.now for grouping via parse_timestamp fallback' do
        fixed_now = Time.utc(2025, 7, 4, 9, 30, 0)
        allow(Time).to receive(:now).and_return(fixed_now)

        activities = [
          { 'timestamp' => 'not-a-time', 'action' => 'login' }
        ]

        timeline = reporter.format_timeline(activities, :day)

        expect(timeline.length).to eq(1)
        expect(timeline[0][:period]).to eq('2025-07-04')
        expect(timeline[0][:actions]).to eq({ 'login' => 1 })
      end
    end
  end

  describe '#export_to_json' do
    let(:report_hash) do
      {
        user_id: 'u1',
        generated_at: '2025-01-01T00:00:00Z',
        summary: { total_actions: 1 }
      }
    end

    context 'when no filepath is provided' do
      it 'returns pretty JSON in :data with success true' do
        result = reporter.export_to_json(report_hash)

        expect(result[:success]).to eq(true)
        expect(result[:data]).to be_a(String)
        expect(result[:data]).to include("\n")
        expect(JSON.parse(result[:data])['user_id']).to eq('u1')
      end
    end

    context 'when a filepath is provided' do
      let(:filepath) { 'tmp/report.json' }

      it 'writes JSON to disk and returns filepath and size' do
        json_data = JSON.pretty_generate(report_hash)
        expect(File).to receive(:write).with(filepath, json_data)

        result = reporter.export_to_json(report_hash, filepath)

        expect(result).to eq({ success: true, filepath: filepath, size: json_data.bytesize })
      end
    end

    context 'when an exception is raised while exporting' do
      it 'returns success false with the error message' do
        allow(JSON).to receive(:pretty_generate).and_raise(StandardError, 'boom')

        result = reporter.export_to_json(report_hash)

        expect(result[:success]).to eq(false)
        expect(result[:error]).to eq('boom')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than 2 users are provided' do
      it 'returns an error report' do
        fixed_time = Time.utc(2025, 1, 1, 1, 2, 3)
        allow(Time).to receive(:now).and_return(fixed_time)

        result = reporter.compare_users(['u1'])

        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'when 2 or more users are provided' do
      let(:user_ids) { %w[u1 u2 u3] }

      let(:stats_by_user) do
        {
          'u1' => { total_actions: 10, unique_actions: 2, action_counts: {}, first_activity: 't1', last_activity: 't2',
                    most_frequent: 'login' },
          'u2' => { total_actions: 3, unique_actions: 1, action_counts: {}, first_activity: 't1', last_activity: 't2',
                    most_frequent: 'view' },
          'u3' => { total_actions: 20, unique_actions: 5, action_counts: {}, first_activity: 't1', last_activity: 't2',
                    most_frequent: 'purchase' }
        }
      end

      let(:activities_by_user) do
        {
          'u1' => [{ 'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'login' }],
          'u2' => [{ 'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'view' }],
          'u3' => [{ 'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'purchase' }]
        }
      end

      let(:scores_by_user) do
        {
          'u1' => 50.0,
          'u2' => 99.0,
          'u3' => 75.0
        }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities) do |uid|
          activities_by_user.fetch(uid)
        end

        allow(reporter).to receive(:fetch_activity_stats) do |uid|
          stats_by_user.fetch(uid)
        end

        allow(reporter).to receive(:fetch_user_score) do |acts|
          uid = activities_by_user.find do |_, a|
            a.equal?(acts)
          end&.first
          scores_by_user.fetch(uid)
        end
      end

      it 'returns comparisons sorted by engagement_score descending' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map do |c|
          c[:user_id]
        end).to eq(%w[u2 u3 u1])
      end

      it 'includes expected comparison fields' do
        result = reporter.compare_users(user_ids)

        first = result[:comparisons].first
        expect(first.keys).to contain_exactly(:user_id, :total_actions, :engagement_score, :most_frequent_action)

        u2_comp = result[:comparisons].find do |c|
          c[:user_id] == 'u2'
        end
        expect(u2_comp[:total_actions]).to eq(3)
        expect(u2_comp[:engagement_score]).to eq(99.0)
        expect(u2_comp[:most_frequent_action]).to eq('view')
      end

      it 'returns top_user as the highest engagement user' do
        result = reporter.compare_users(user_ids)

        expect(result[:top_user]).to eq('u2')
      end

      it 'returns average_score rounded to 2 decimals' do
        result = reporter.compare_users(user_ids)

        expected = ((99.0 + 75.0 + 50.0) / 3.0).round(2)
        expect(result[:average_score]).to eq(expected)
      end

      it 'handles ties by keeping original order among tied users (stable insertion behavior)' do
        allow(reporter).to receive(:fetch_user_score) do |acts|
          uid = activities_by_user.find do |_, a|
            a.equal?(acts)
          end&.first
          { 'u1' => 80.0, 'u2' => 90.0, 'u3' => 80.0 }.fetch(uid)
        end

        result = reporter.compare_users(user_ids)

        expect(result[:comparisons].map do |c|
          c[:user_id]
        end).to eq(%w[u2 u1 u3])
      end
    end
  end
end
