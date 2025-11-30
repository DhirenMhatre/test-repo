require 'spec_helper'
require 'tmpdir'
require 'time'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  describe '#initialize' do
    context 'with default URLs' do
      let(:reporter) { described_class.new }

      it 'sets default Go service URL' do
        expect(reporter.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
      end

      it 'sets default Python service URL' do
        expect(reporter.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
      end
    end

    context 'with custom URLs' do
      let(:go_url) { 'http://go.example.com:9090' }
      let(:py_url) { 'http://py.example.com:9091' }
      let(:reporter) { described_class.new(go_service_url: go_url, python_service_url: py_url) }

      it 'stores the provided Go service URL' do
        expect(reporter.instance_variable_get(:@go_service_url)).to eq(go_url)
      end

      it 'stores the provided Python service URL' do
        expect(reporter.instance_variable_get(:@python_service_url)).to eq(py_url)
      end
    end
  end

  describe '#generate_report' do
    let(:reporter) { described_class.new }
    let(:user_id) { 42 }

    context 'when no activities are found for the user' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report and does not call other fetchers' do
        expect(reporter).not_to receive(:fetch_activity_stats)
        expect(reporter).not_to receive(:fetch_activity_patterns)
        expect(reporter).not_to receive(:fetch_user_score)
        expect(reporter).not_to receive(:fetch_anomalies)

        result = reporter.generate_report(user_id)
        expect(result).to include(error: true, message: 'No activities found')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'when activities are present' do
      let(:fixed_now) { Time.utc(2025, 1, 1, 0, 0, 0) }
      let(:activities) do
        [
          { 'timestamp' => '2025-05-01T10:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-05-01T12:00:00Z', 'action' => 'click' }
        ]
      end
      let(:stats) do
        {
          total_actions: 2,
          unique_actions: 2,
          action_counts: { 'login' => 1, 'click' => 1 },
          first_activity: '2025-05-01T10:00:00Z',
          last_activity: '2025-05-01T12:00:00Z',
          most_frequent: 'login'
        }
      end
      let(:patterns) do
        [
          { 'pattern_type' => 'sequence', 'description' => 'Morning logins', 'confidence' => 0.9 },
          { 'pattern_type' => 'burst', 'description' => 'Click spree', 'confidence' => 0.7 }
        ]
      end
      let(:user_score) { 80.5 }
      let(:anomalies) { [{ 'action' => 'hack', 'timestamp' => '2025-05-01T13:00:00Z' }] }

      before do
        allow(Time).to receive(:now).and_return(fixed_now)
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report with expected fields and values' do
        report = reporter.generate_report(user_id, group_by: :day)

        expect(report[:user_id]).to eq(user_id)
        expect(report[:generated_at]).to eq(fixed_now.iso8601)

        expect(report[:summary]).to include(
          total_actions: 2,
          unique_actions: 2,
          engagement_score: user_score,
          first_activity: '2025-05-01T10:00:00Z',
          last_activity: '2025-05-01T12:00:00Z'
        )

        expect(report[:action_breakdown]).to eq({ 'login' => 1, 'click' => 1 })

        expect(report[:patterns]).to eq([
                                          { type: 'sequence', description: 'Morning logins', confidence: 0.9 },
                                          { type: 'burst', description: 'Click spree', confidence: 0.7 }
                                        ])

        expect(report[:anomalies]).to eq(anomalies)

        expect(report[:timeline]).to eq([
                                          {
                                            period: '2025-05-01',
                                            total_actions: 2,
                                            actions: { 'login' => 1, 'click' => 1 },
                                            first_timestamp: '2025-05-01T10:00:00Z',
                                            last_timestamp: '2025-05-01T12:00:00Z'
                                          }
                                        ])

        expect(report[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(report[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(report[:insights]).not_to include('Low engagement - consider re-engagement strategies')
      end

      it 'honors the provided group_by option when building the timeline' do
        report = reporter.generate_report(user_id, group_by: :hour)
        expect(report[:timeline].map { |e| e[:period] }).to contain_exactly('2025-05-01 10:00', '2025-05-01 12:00')
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) { described_class.new }

    context 'when activities is empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'grouping by day including an invalid timestamp' do
      let(:fixed_now) { Time.utc(2025, 1, 2, 12, 0, 0) }
      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T01:10:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T23:59:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-02T00:05:00Z', 'action' => 'login' },
          { 'timestamp' => 'bad', 'action' => 'login' }
        ]
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_now)
      end

      it 'groups correctly by day and handles invalid timestamps gracefully' do
        timeline = reporter.format_timeline(activities, :day)

        expect(timeline).to eq([
                                 {
                                   period: '2025-01-01',
                                   total_actions: 2,
                                   actions: { 'login' => 1, 'click' => 1 },
                                   first_timestamp: '2025-01-01T01:10:00Z',
                                   last_timestamp: '2025-01-01T23:59:00Z'
                                 },
                                 {
                                   period: '2025-01-02',
                                   total_actions: 2,
                                   actions: { 'login' => 2 },
                                   first_timestamp: '2025-01-02T00:05:00Z',
                                   last_timestamp: 'bad'
                                 }
                               ])
      end
    end

    context 'grouping by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2025-02-01T10:05:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-02-01T10:30:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-02-01T11:00:00Z', 'action' => 'login' }
        ]
      end

      it 'returns buckets per hour with correct counts and ordering' do
        timeline = reporter.format_timeline(activities, :hour)
        expect(timeline).to eq([
                                 {
                                   period: '2025-02-01 10:00',
                                   total_actions: 2,
                                   actions: { 'login' => 1, 'click' => 1 },
                                   first_timestamp: '2025-02-01T10:05:00Z',
                                   last_timestamp: '2025-02-01T10:30:00Z'
                                 },
                                 {
                                   period: '2025-02-01 11:00',
                                   total_actions: 1,
                                   actions: { 'login' => 1 },
                                   first_timestamp: '2025-02-01T11:00:00Z',
                                   last_timestamp: '2025-02-01T11:00:00Z'
                                 }
                               ])
      end
    end

    context 'grouping by week' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T08:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-04T09:00:00Z', 'action' => 'click' }
        ]
      end

      it 'uses ISO week format in the period' do
        timeline = reporter.format_timeline(activities, :week)
        expect(timeline.length).to eq(1)
        expect(timeline.first[:period]).to match(/\A2025-W0?\d+\z/)
        expect(timeline.first[:total_actions]).to eq(2)
        expect(timeline.first[:actions]).to eq({ 'login' => 1, 'click' => 1 })
      end
    end

    context 'grouping by month' do
      let(:activities) do
        [
          { 'timestamp' => '2025-03-01T00:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-03-31T23:59:59Z', 'action' => 'click' }
        ]
      end

      it 'uses YYYY-MM format for month' do
        timeline = reporter.format_timeline(activities, :month)
        expect(timeline.map { |e| e[:period] }).to eq(['2025-03'])
        expect(timeline.first[:total_actions]).to eq(2)
      end
    end

    context 'with unsupported group_by value' do
      let(:activities) do
        [
          { 'timestamp' => '2025-04-10T10:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-04-10T11:00:00Z', 'action' => 'click' }
        ]
      end

      it 'falls back to day grouping' do
        timeline = reporter.format_timeline(activities, :unknown)
        expect(timeline.length).to eq(1)
        expect(timeline.first[:period]).to eq('2025-04-10')
      end
    end
  end

  describe '#export_to_json' do
    let(:reporter) { described_class.new }
    let(:report) do
      {
        user_id: 1,
        summary: { total_actions: 3 },
        data: %w[a b c]
      }
    end

    context 'when no filepath is provided' do
      it 'returns success with JSON data' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be(true)
        expect(result[:data]).to be_a(String)
        expect(JSON.parse(result[:data])).to eq(JSON.parse(JSON.pretty_generate(report)))
      end
    end

    context 'when a filepath is provided' do
      it 'writes the file and returns file metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be(true)
          expect(result[:filepath]).to eq(path)
          expect(result[:size]).to eq(JSON.pretty_generate(report).bytesize)
          content = File.read(path)
          expect(JSON.parse(content)).to eq(JSON.parse(JSON.pretty_generate(report)))
        end
      end
    end

    context 'when writing the file raises an error' do
      it 'returns an error result' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          allow(File).to receive(:write).with(path, kind_of(String)).and_raise(StandardError.new('disk full'))
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be(false)
          expect(result[:error]).to include('disk full')
        end
      end
    end
  end

  describe '#compare_users' do
    let(:reporter) { described_class.new }

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users([1])
        expect(result).to include(error: true, message: 'At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with multiple users' do
      let(:user_ids) { [1, 2, 3] }
      let(:activities_1) { [{ 'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'login' }] }
      let(:activities_2) { [{ 'timestamp' => '2025-01-02T00:00:00Z', 'action' => 'click' }] }
      let(:activities_3) { [{ 'timestamp' => '2025-01-03T00:00:00Z', 'action' => 'view' }] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(1).and_return(activities_1)
        allow(reporter).to receive(:fetch_user_activities).with(2).and_return(activities_2)
        allow(reporter).to receive(:fetch_user_activities).with(3).and_return(activities_3)

        allow(reporter).to receive(:fetch_activity_stats).with(1).and_return(
          total_actions: 30,
          unique_actions: 5,
          action_counts: { 'login' => 20, 'click' => 10 },
          first_activity: '2025-01-01T00:00:00Z',
          last_activity: '2025-01-10T00:00:00Z',
          most_frequent: 'login'
        )
        allow(reporter).to receive(:fetch_activity_stats).with(2).and_return(
          total_actions: 20,
          unique_actions: 4,
          action_counts: { 'click' => 15, 'login' => 5 },
          first_activity: '2025-01-02T00:00:00Z',
          last_activity: '2025-01-09T00:00:00Z',
          most_frequent: 'click'
        )
        allow(reporter).to receive(:fetch_activity_stats).with(3).and_return(
          total_actions: 10,
          unique_actions: 3,
          action_counts: { 'view' => 8, 'login' => 2 },
          first_activity: '2025-01-03T00:00:00Z',
          last_activity: '2025-01-08T00:00:00Z',
          most_frequent: 'view'
        )

        allow(reporter).to receive(:fetch_user_score).with(activities_1).and_return(90.0)
        allow(reporter).to receive(:fetch_user_score).with(activities_2).and_return(50.2)
        allow(reporter).to receive(:fetch_user_score).with(activities_3).and_return(10.5)
      end

      it 'compares users and sorts by engagement score descending' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq([1, 2, 3])
        expect(result[:comparisons][0]).to include(user_id: 1, total_actions: 30, engagement_score: 90.0,
                                                   most_frequent_action: 'login')
        expect(result[:comparisons][1]).to include(user_id: 2, total_actions: 20, engagement_score: 50.2,
                                                   most_frequent_action: 'click')
        expect(result[:comparisons][2]).to include(user_id: 3, total_actions: 10, engagement_score: 10.5,
                                                   most_frequent_action: 'view')

        expect(result[:top_user]).to eq(1)
        expect(result[:average_score]).to eq(((90.0 + 50.2 + 10.5) / 3.0).round(2))
      end

      it 'invokes activity and scoring fetchers for each user' do
        reporter.compare_users(user_ids)
        user_ids.each do |uid|
          expect(reporter).to have_received(:fetch_user_activities).with(uid)
          expect(reporter).to have_received(:fetch_activity_stats).with(uid)
        end
      end
    end
  end
end
