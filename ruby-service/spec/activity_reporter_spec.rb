require 'spec_helper'
require 'json'
require 'time'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new(
      go_service_url: 'http://example-go:8080',
      python_service_url: 'http://example-python:8081'
    )
  end

  describe '#generate_report' do
    let(:user_id) do
      'user-1'
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report with appropriate message' do
        result = reporter.generate_report(user_id)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect { Time.iso8601(result[:generated_at]) }.not_to raise_error
      end
    end

    context 'with activities and stats available' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-01T10:15:00Z', 'action' => 'click', 'meta' => {} },
          { 'timestamp' => '2023-05-01T12:00:00Z', 'action' => 'view', 'meta' => {} },
          { 'timestamp' => '2023-05-02T09:00:00Z', 'action' => 'click', 'meta' => {} }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 2,
          action_counts: { 'click' => 2, 'view' => 1 },
          first_activity: '2023-05-01T10:15:00Z',
          last_activity: '2023-05-02T09:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'streak', 'description' => 'Daily login streak', 'confidence' => 0.92 },
          { 'pattern_type' => 'hourly', 'description' => 'Morning activity spike', 'confidence' => 0.75 }
        ]
      end

      let(:user_score) do
        82.5
      end

      let(:anomalies) do
        [{ 'timestamp' => '2023-05-02T09:00:00Z', 'action' => 'suspicious' }]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report with summary, patterns, anomalies, timeline and insights (grouped by default day)' do
        result = reporter.generate_report(user_id)

        expect(result[:user_id]).to eq(user_id)
        expect { Time.iso8601(result[:generated_at]) }.not_to raise_error

        expect(result[:summary][:total_actions]).to eq(3)
        expect(result[:summary][:unique_actions]).to eq(2)
        expect(result[:summary][:engagement_score]).to eq(user_score)
        expect(result[:summary][:first_activity]).to eq('2023-05-01T10:15:00Z')
        expect(result[:summary][:last_activity]).to eq('2023-05-02T09:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'click' => 2, 'view' => 1 })

        expect(result[:patterns]).to eq([
                                          { type: 'streak', description: 'Daily login streak', confidence: 0.92 },
                                          { type: 'hourly', description: 'Morning activity spike', confidence: 0.75 }
                                        ])

        expect(result[:anomalies]).to eq(anomalies)

        expect(result[:timeline]).to eq([
                                          {
                                            period: '2023-05-01',
                                            total_actions: 2,
                                            actions: { 'click' => 1, 'view' => 1 },
                                            first_timestamp: '2023-05-01T10:15:00Z',
                                            last_timestamp: '2023-05-01T12:00:00Z'
                                          },
                                          {
                                            period: '2023-05-02',
                                            total_actions: 1,
                                            actions: { 'click' => 1 },
                                            first_timestamp: '2023-05-02T09:00:00Z',
                                            last_timestamp: '2023-05-02T09:00:00Z'
                                          }
                                        ])

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights].any? do |s|
          s.include?('anomalous activities detected')
        end).to be true
      end

      it 'allows grouping the timeline by hour via options' do
        result = reporter.generate_report(user_id, group_by: :hour)
        expect(result[:timeline]).to eq([
                                          {
                                            period: '2023-05-01 10:00',
                                            total_actions: 1,
                                            actions: { 'click' => 1 },
                                            first_timestamp: '2023-05-01T10:15:00Z',
                                            last_timestamp: '2023-05-01T10:15:00Z'
                                          },
                                          {
                                            period: '2023-05-01 12:00',
                                            total_actions: 1,
                                            actions: { 'view' => 1 },
                                            first_timestamp: '2023-05-01T12:00:00Z',
                                            last_timestamp: '2023-05-01T12:00:00Z'
                                          },
                                          {
                                            period: '2023-05-02 09:00',
                                            total_actions: 1,
                                            actions: { 'click' => 1 },
                                            first_timestamp: '2023-05-02T09:00:00Z',
                                            last_timestamp: '2023-05-02T09:00:00Z'
                                          }
                                        ])
      end

      it 'generates extensive insights when thresholds are exceeded' do
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return({
                                                                                     total_actions: 150,
                                                                                     unique_actions: 12,
                                                                                     action_counts: { 'a' => 100,
                                                                                                      'b' => 50 },
                                                                                     first_activity: '2023-05-01T10:15:00Z',
                                                                                     last_activity: '2023-05-02T09:00:00Z',
                                                                                     most_frequent: 'a'
                                                                                   })
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return([
                                                                                           { 'pattern_type' => 'p1',
                                                                                             'description' => 'd1', 'confidence' => 0.9 },
                                                                                           { 'pattern_type' => 'p2',
                                                                                             'description' => 'd2', 'confidence' => 0.8 },
                                                                                           { 'pattern_type' => 'p3',
                                                                                             'description' => 'd3', 'confidence' => 0.7 }
                                                                                         ])
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(95.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([{ a: 1 }, { b: 2 }])

        result = reporter.generate_report(user_id)

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('2 anomalous activities detected - review recommended')
        expect(result[:insights]).to include('Power user - high volume of activities')
      end

      it 'generates low engagement insights when score is small' do
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(30.0)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return([])
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([{ only: 'one' }])
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return({
                                                                                     total_actions: 3,
                                                                                     unique_actions: 2,
                                                                                     action_counts: { 'x' => 3 },
                                                                                     first_activity: '2023-05-01T00:00:00Z',
                                                                                     last_activity: '2023-05-02T00:00:00Z',
                                                                                     most_frequent: 'x'
                                                                                   })

        result = reporter.generate_report(user_id)
        expect(result[:insights]).to include('Low engagement - consider re-engagement strategies')
        expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(result[:insights].any? do |s|
          s.include?('Power user')
        end).to be false
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities is empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'when grouping by day' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-01T10:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2023-05-01T12:00:00Z', 'action' => 'b' },
          { 'timestamp' => '2023-05-02T09:00:00Z', 'action' => 'a' }
        ]
      end

      it 'groups activities per day with counts and preserves first/last order within group' do
        result = reporter.format_timeline(activities, :day)
        expect(result).to eq([
                               {
                                 period: '2023-05-01',
                                 total_actions: 2,
                                 actions: { 'a' => 1, 'b' => 1 },
                                 first_timestamp: '2023-05-01T10:00:00Z',
                                 last_timestamp: '2023-05-01T12:00:00Z'
                               },
                               {
                                 period: '2023-05-02',
                                 total_actions: 1,
                                 actions: { 'a' => 1 },
                                 first_timestamp: '2023-05-02T09:00:00Z',
                                 last_timestamp: '2023-05-02T09:00:00Z'
                               }
                             ])
      end
    end

    context 'when grouping by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-01T10:15:00Z', 'action' => 'a' },
          { 'timestamp' => '2023-05-01T10:45:00Z', 'action' => 'a' },
          { 'timestamp' => '2023-05-01T11:00:00Z', 'action' => 'b' }
        ]
      end

      it 'groups by hour keys with correct string formatting and sorting' do
        result = reporter.format_timeline(activities, :hour)
        expect(result).to eq([
                               {
                                 period: '2023-05-01 10:00',
                                 total_actions: 2,
                                 actions: { 'a' => 2 },
                                 first_timestamp: '2023-05-01T10:15:00Z',
                                 last_timestamp: '2023-05-01T10:45:00Z'
                               },
                               {
                                 period: '2023-05-01 11:00',
                                 total_actions: 1,
                                 actions: { 'b' => 1 },
                                 first_timestamp: '2023-05-01T11:00:00Z',
                                 last_timestamp: '2023-05-01T11:00:00Z'
                               }
                             ])
      end
    end

    context 'when grouping by week and month' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-01T10:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2023-05-10T10:00:00Z', 'action' => 'b' },
          { 'timestamp' => '2023-06-02T10:00:00Z', 'action' => 'a' }
        ]
      end

      it 'groups by week using ISO week numbers' do
        wk1 = Time.parse('2023-05-01T10:00:00Z').strftime('%Y-W%V')
        wk2 = Time.parse('2023-05-10T10:00:00Z').strftime('%Y-W%V')
        wk3 = Time.parse('2023-06-02T10:00:00Z').strftime('%Y-W%V')

        result = reporter.format_timeline(activities, :week)
        expect(result).to eq([
                               {
                                 period: wk1,
                                 total_actions: 1,
                                 actions: { 'a' => 1 },
                                 first_timestamp: '2023-05-01T10:00:00Z',
                                 last_timestamp: '2023-05-01T10:00:00Z'
                               },
                               {
                                 period: wk2,
                                 total_actions: 1,
                                 actions: { 'b' => 1 },
                                 first_timestamp: '2023-05-10T10:00:00Z',
                                 last_timestamp: '2023-05-10T10:00:00Z'
                               },
                               {
                                 period: wk3,
                                 total_actions: 1,
                                 actions: { 'a' => 1 },
                                 first_timestamp: '2023-06-02T10:00:00Z',
                                 last_timestamp: '2023-06-02T10:00:00Z'
                               }
                             ])
      end

      it 'groups by month with correct keys' do
        result = reporter.format_timeline(activities, :month)
        expect(result).to eq([
                               {
                                 period: '2023-05',
                                 total_actions: 2,
                                 actions: { 'a' => 1, 'b' => 1 },
                                 first_timestamp: '2023-05-01T10:00:00Z',
                                 last_timestamp: '2023-05-10T10:00:00Z'
                               },
                               {
                                 period: '2023-06',
                                 total_actions: 1,
                                 actions: { 'a' => 1 },
                                 first_timestamp: '2023-06-02T10:00:00Z',
                                 last_timestamp: '2023-06-02T10:00:00Z'
                               }
                             ])
      end
    end

    context 'when group_by value is unknown' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-01T10:00:00Z', 'action' => 'x' },
          { 'timestamp' => '2023-05-01T11:00:00Z', 'action' => 'y' }
        ]
      end

      it 'defaults to day grouping' do
        result = reporter.format_timeline(activities, :unknown)
        expect(result).to eq([
                               {
                                 period: '2023-05-01',
                                 total_actions: 2,
                                 actions: { 'x' => 1, 'y' => 1 },
                                 first_timestamp: '2023-05-01T10:00:00Z',
                                 last_timestamp: '2023-05-01T11:00:00Z'
                               }
                             ])
      end
    end

    context 'when an activity has an invalid timestamp' do
      it 'falls back to Time.now for grouping while preserving original timestamps in output' do
        fixed_now = Time.new(2023, 1, 2, 13, 45, 0, '+00:00')
        allow(Time).to receive(:now).and_return(fixed_now)

        activities = [
          { 'timestamp' => 'invalid', 'action' => 'x' }
        ]
        result = reporter.format_timeline(activities, :day)
        expect(result.size).to eq(1)
        expect(result.first[:period]).to eq('2023-01-02')
        expect(result.first[:first_timestamp]).to eq('invalid')
        expect(result.first[:last_timestamp]).to eq('invalid')
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      { test: 'ok', nested: { a: 1 } }
    end

    context 'when filepath is not provided' do
      it 'returns success with data as pretty JSON' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be true
        expect(result[:data]).to eq(JSON.pretty_generate(report))
        expect { JSON.parse(result[:data]) }.not_to raise_error
      end
    end

    context 'when filepath is provided' do
      it 'writes the file and returns path and size' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(path)
          expect(result[:size]).to eq(JSON.pretty_generate(report).bytesize)
          written = File.read(path)
          expect(written).to eq(JSON.pretty_generate(report))
        end
      end
    end

    context 'when writing the file raises an error' do
      it 'returns a failure with the error message' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        result = reporter.export_to_json(report, '/unwritable/path.json')
        expect(result[:success]).to be false
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['u1'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
      end
    end

    context 'with multiple users and varying scores' do
      let(:user_ids) do
        %w[u1 u2 u3]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{ a: 1 }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{ b: 2 }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([{ c: 3 }])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 10, unique_actions: 3,
                                                                                  action_counts: {}, first_activity: 't1', last_activity: 't2', most_frequent: 'x' })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 5, unique_actions: 2,
                                                                                  action_counts: {}, first_activity: 't1', last_activity: 't2', most_frequent: 'y' })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 20, unique_actions: 4,
                                                                                  action_counts: {}, first_activity: 't1', last_activity: 't2', most_frequent: 'z' })

        allow(reporter).to receive(:fetch_user_score).and_return(70.0, 85.5, 60.25)
      end

      it 'returns a sorted comparison by engagement score with top user and average score' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)

        comparisons = result[:comparisons]
        expect(comparisons.map do |c|
          c[:user_id]
        end).to eq(%w[u2 u1 u3])

        expect(comparisons.find do |c|
          c[:user_id] == 'u2'
        end[:engagement_score]).to eq(85.5)

        expect(comparisons.find do |c|
          c[:user_id] == 'u1'
        end[:total_actions]).to eq(10)

        expect(comparisons.find do |c|
          c[:user_id] == 'u3'
        end[:most_frequent]).to eq('z')

        expect(result[:top_user]).to eq('u2')
        expect(result[:average_score]).to eq(((70.0 + 85.5 + 60.25) / 3.0).round(2))
      end
    end

    context 'when two users have equal scores' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('a').and_return([{ a: 1 }])
        allow(reporter).to receive(:fetch_user_activities).with('b').and_return([{ b: 1 }])

        allow(reporter).to receive(:fetch_activity_stats).with('a').and_return({ total_actions: 1, unique_actions: 1,
                                                                                 action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'a' })
        allow(reporter).to receive(:fetch_activity_stats).with('b').and_return({ total_actions: 1, unique_actions: 1,
                                                                                 action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'b' })

        allow(reporter).to receive(:fetch_user_score).and_return(50.0, 50.0)
      end

      it 'keeps the original order for ties and computes average' do
        result = reporter.compare_users(%w[a b])
        ids = result[:comparisons].map do |c|
          c[:user_id]
        end
        expect(ids).to eq(%w[a b])
        expect(result[:top_user]).to eq('a')
        expect(result[:average_score]).to eq(50.0)
      end
    end
  end
end
