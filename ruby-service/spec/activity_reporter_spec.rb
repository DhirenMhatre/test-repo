require 'spec_helper'
require 'json'
require 'rails_helper'
require_relative '../ruby-service/app/activity_reporter'

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
      let(:reporter) do
        described_class.new(
          go_service_url: 'http://go.example.com',
          python_service_url: 'http://py.example.com'
        )
      end

      it 'stores provided service URLs' do
        expect(reporter.instance_variable_get(:@go_service_url)).to eq('http://go.example.com')
        expect(reporter.instance_variable_get(:@python_service_url)).to eq('http://py.example.com')
      end
    end
  end

  describe '#generate_report' do
    let(:reporter) { described_class.new }
    let(:user_id) { 42 }
    let(:now) { Time.utc(2025, 1, 10, 12, 0, 0) }

    before do
      allow(Time).to receive(:now).and_return(now)
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report(user_id)
        expect(result[:error]).to be(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(now.iso8601)
      end
    end

    context 'when activities are present' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T10:15:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-01T11:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2025-01-02T09:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-08T12:00:00Z', 'action' => 'share' }
        ]
      end

      let(:stats) do
        {
          total_actions: 4,
          unique_actions: 3,
          action_counts: { 'click' => 2, 'view' => 1, 'share' => 1 },
          first_activity: '2025-01-01T10:15:00Z',
          last_activity: '2025-01-08T12:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'daily', 'description' => 'Active every day', 'confidence' => 0.9 },
          { 'pattern_type' => 'weekly', 'description' => 'Active on Wednesdays', 'confidence' => 0.7 }
        ]
      end

      let(:anomalies) do
        [
          { 'id' => 1, 'type' => 'anomaly' },
          { 'id' => 2, 'type' => 'anomaly' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(80.5)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a full report with summary, patterns, anomalies, timeline, and insights' do
        result = reporter.generate_report(user_id, group_by: :day)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(now.iso8601)

        expect(result[:summary][:total_actions]).to eq(4)
        expect(result[:summary][:unique_actions]).to eq(3)
        expect(result[:summary][:engagement_score]).to eq(80.5)
        expect(result[:summary][:first_activity]).to eq('2025-01-01T10:15:00Z')
        expect(result[:summary][:last_activity]).to eq('2025-01-08T12:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'click' => 2, 'view' => 1, 'share' => 1 })

        expected_patterns = patterns.map do |p|
          {
            type: p['pattern_type'],
            description: p['description'],
            confidence: p['confidence']
          }
        end
        expect(result[:patterns]).to eq(expected_patterns)

        expect(result[:anomalies]).to eq(anomalies)

        expect(result[:timeline]).to eq([
                                          {
                                            period: '2025-01-01',
                                            total_actions: 2,
                                            actions: { 'click' => 1, 'view' => 1 },
                                            first_timestamp: '2025-01-01T10:15:00Z',
                                            last_timestamp: '2025-01-01T11:00:00Z'
                                          },
                                          {
                                            period: '2025-01-02',
                                            total_actions: 1,
                                            actions: { 'click' => 1 },
                                            first_timestamp: '2025-01-02T09:00:00Z',
                                            last_timestamp: '2025-01-02T09:00:00Z'
                                          },
                                          {
                                            period: '2025-01-08',
                                            total_actions: 1,
                                            actions: { 'share' => 1 },
                                            first_timestamp: '2025-01-08T12:00:00Z',
                                            last_timestamp: '2025-01-08T12:00:00Z'
                                          }
                                        ])

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('2 anomalous activities detected - review recommended')
        expect(result[:insights]).not_to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).not_to include('Clear behavioral patterns detected')
        expect(result[:insights]).not_to include('Power user - high volume of activities')
      end

      it 'supports grouping by hour' do
        result = reporter.generate_report(user_id, group_by: :hour)
        expect(result[:timeline]).to eq([
                                          {
                                            period: '2025-01-01 10:00',
                                            total_actions: 1,
                                            actions: { 'click' => 1 },
                                            first_timestamp: '2025-01-01T10:15:00Z',
                                            last_timestamp: '2025-01-01T10:15:00Z'
                                          },
                                          {
                                            period: '2025-01-01 11:00',
                                            total_actions: 1,
                                            actions: { 'view' => 1 },
                                            first_timestamp: '2025-01-01T11:00:00Z',
                                            last_timestamp: '2025-01-01T11:00:00Z'
                                          },
                                          {
                                            period: '2025-01-02 09:00',
                                            total_actions: 1,
                                            actions: { 'click' => 1 },
                                            first_timestamp: '2025-01-02T09:00:00Z',
                                            last_timestamp: '2025-01-02T09:00:00Z'
                                          },
                                          {
                                            period: '2025-01-08 12:00',
                                            total_actions: 1,
                                            actions: { 'share' => 1 },
                                            first_timestamp: '2025-01-08T12:00:00Z',
                                            last_timestamp: '2025-01-08T12:00:00Z'
                                          }
                                        ])
      end

      it 'falls back to day grouping for unknown group_by' do
        result = reporter.generate_report(user_id, group_by: :unknown)
        periods = result[:timeline].map do |entry|
          entry[:period]
        end
        expect(periods).to eq(%w[2025-01-01 2025-01-02 2025-01-08])
      end

      it 'supports grouping by month' do
        result = reporter.generate_report(user_id, group_by: :month)
        expect(result[:timeline]).to eq([
                                          {
                                            period: '2025-01',
                                            total_actions: 4,
                                            actions: { 'click' => 2, 'view' => 1, 'share' => 1 },
                                            first_timestamp: '2025-01-01T10:15:00Z',
                                            last_timestamp: '2025-01-08T12:00:00Z'
                                          }
                                        ])
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) { described_class.new }

    context 'with empty activities' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'with activities across days' do
      let(:activities) do
        [
          { 'timestamp' => '2025-02-01T05:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2025-02-01T06:00:00Z', 'action' => 'b' },
          { 'timestamp' => '2025-02-02T07:00:00Z', 'action' => 'a' }
        ]
      end

      it 'groups by day by default and sorts by period' do
        result = reporter.format_timeline(activities)
        expect(result).to eq([
                               {
                                 period: '2025-02-01',
                                 total_actions: 2,
                                 actions: { 'a' => 1, 'b' => 1 },
                                 first_timestamp: '2025-02-01T05:00:00Z',
                                 last_timestamp: '2025-02-01T06:00:00Z'
                               },
                               {
                                 period: '2025-02-02',
                                 total_actions: 1,
                                 actions: { 'a' => 1 },
                                 first_timestamp: '2025-02-02T07:00:00Z',
                                 last_timestamp: '2025-02-02T07:00:00Z'
                               }
                             ])
      end
    end

    context 'with activities across hours' do
      let(:activities) do
        [
          { 'timestamp' => '2025-03-10T00:30:00Z', 'action' => 'x' },
          { 'timestamp' => '2025-03-10T00:45:00Z', 'action' => 'y' },
          { 'timestamp' => '2025-03-10T01:15:00Z', 'action' => 'x' }
        ]
      end

      it 'groups by hour when specified' do
        result = reporter.format_timeline(activities, :hour)
        expect(result).to eq([
                               {
                                 period: '2025-03-10 00:00',
                                 total_actions: 2,
                                 actions: { 'x' => 1, 'y' => 1 },
                                 first_timestamp: '2025-03-10T00:30:00Z',
                                 last_timestamp: '2025-03-10T00:45:00Z'
                               },
                               {
                                 period: '2025-03-10 01:00',
                                 total_actions: 1,
                                 actions: { 'x' => 1 },
                                 first_timestamp: '2025-03-10T01:15:00Z',
                                 last_timestamp: '2025-03-10T01:15:00Z'
                               }
                             ])
      end
    end

    context 'with activities in non-chronological order' do
      let(:activities) do
        [
          { 'timestamp' => '2025-04-01T12:00:00Z', 'action' => 'late' },
          { 'timestamp' => '2025-04-01T09:00:00Z', 'action' => 'early' }
        ]
      end

      it 'preserves input order within a period for first/last timestamps' do
        result = reporter.format_timeline(activities, :day)
        expect(result.first[:first_timestamp]).to eq('2025-04-01T12:00:00Z')
        expect(result.first[:last_timestamp]).to eq('2025-04-01T09:00:00Z')
      end
    end
  end

  describe '#export_to_json' do
    let(:reporter) { described_class.new }
    let(:report) do
      {
        user_id: 1,
        summary: { total_actions: 2 },
        timeline: []
      }
    end

    context 'when no filepath is provided' do
      it 'returns pretty JSON data' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be(true)
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq(1)
        expect(parsed['summary']).to eq({ 'total_actions' => 2 })
      end
    end

    context 'when filepath is provided' do
      let(:path) { '/tmp/report.json' }

      before do
        allow(File).to receive(:write).and_return(nil)
      end

      it 'writes the file and returns metadata' do
        expected_json = JSON.pretty_generate(report)
        result = reporter.export_to_json(report, path)
        expect(File).to have_received(:write).with(path, expected_json)
        expect(result[:success]).to be(true)
        expect(result[:filepath]).to eq(path)
        expect(result[:size]).to eq(expected_json.bytesize)
      end
    end

    context 'when an error occurs during file write' do
      let(:path) { '/root/forbidden/report.json' }

      before do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      end

      it 'returns an error hash' do
        result = reporter.export_to_json(report, path)
        expect(result[:success]).to be(false)
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    let(:reporter) { described_class.new }

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users([1])
        expect(result[:error]).to be(true)
        expect(result[:message]).to eq('At least 2 users required')
      end
    end

    context 'with multiple users' do
      let(:user_ids) { [1, 2, 3] }

      let(:acts1) { [{ 'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'a' }] }
      let(:acts2) { [{ 'timestamp' => '2025-01-02T00:00:00Z', 'action' => 'b' }] }
      let(:acts3) { [{ 'timestamp' => '2025-01-03T00:00:00Z', 'action' => 'c' }] }

      let(:stats1) do
        {
          total_actions: 10,
          unique_actions: 2,
          action_counts: { 'a' => 7, 'b' => 3 },
          first_activity: '2025-01-01T00:00:00Z',
          last_activity: '2025-01-05T00:00:00Z',
          most_frequent: 'a'
        }
      end

      let(:stats2) do
        {
          total_actions: 20,
          unique_actions: 3,
          action_counts: { 'b' => 14, 'c' => 6 },
          first_activity: '2025-01-02T00:00:00Z',
          last_activity: '2025-01-06T00:00:00Z',
          most_frequent: 'b'
        }
      end

      let(:stats3) do
        {
          total_actions: 15,
          unique_actions: 4,
          action_counts: { 'c' => 10, 'a' => 5 },
          first_activity: '2025-01-03T00:00:00Z',
          last_activity: '2025-01-07T00:00:00Z',
          most_frequent: 'c'
        }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(1).and_return(acts1)
        allow(reporter).to receive(:fetch_user_activities).with(2).and_return(acts2)
        allow(reporter).to receive(:fetch_user_activities).with(3).and_return(acts3)

        allow(reporter).to receive(:fetch_activity_stats).with(1).and_return(stats1)
        allow(reporter).to receive(:fetch_activity_stats).with(2).and_return(stats2)
        allow(reporter).to receive(:fetch_activity_stats).with(3).and_return(stats3)

        allow(reporter).to receive(:fetch_user_score).with(acts1).and_return(50.0)
        allow(reporter).to receive(:fetch_user_score).with(acts2).and_return(80.0)
        allow(reporter).to receive(:fetch_user_score).with(acts3).and_return(65.25)
      end

      it 'returns comparisons sorted by engagement score with averages' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        expect(result[:top_user]).to eq(2)
        expect(result[:average_score]).to eq(65.08)

        ordered_ids = result[:comparisons].map do |c|
          c[:user_id]
        end
        expect(ordered_ids).to eq([2, 3, 1])

        most_frequent = result[:comparisons].map do |c|
          c[:most_frequent_action]
        end
        expect(most_frequent).to eq(%w[b c a])

        totals = result[:comparisons].map do |c|
          c[:total_actions]
        end
        expect(totals).to eq([20, 15, 10])
      end
    end
  end
end
