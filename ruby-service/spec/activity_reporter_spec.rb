# WARNING: This test file may contain syntax errors
# Generated after 3 attempts with validation errors
# Last error: ruby: /tmp/tmp8xsh3653.rb:358: syntax error, unexpected '}', expecting `end' or dummy end (SyntaxError)
    end }
        ^
# Please review and fix any issues before running

require 'spec_helper'
require 'tmpdir'
require 'rails_helper'
require_relative '../ruby-service/app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) { described_class.new }
  let(:user_id) { 'user-123' }
  let(:now) { Time.utc(2025, 1, 2, 3, 4, 5) }

  before do
    allow(Time).to receive(:now).and_return(now)
  end

  describe '#generate_report' do
    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report with message and timestamp' do
        result = reporter.generate_report(user_id)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(now.iso8601)
      end
    end

    context 'with activities and aggregated stats' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T10:15:00Z' },
          { 'action' => 'view', 'timestamp' => '2025-01-01T11:20:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 2,
          unique_actions: 2,
          action_counts: { 'login' => 1, 'view' => 1 },
          first_activity: '2025-01-01T10:15:00Z',
          last_activity: '2025-01-01T11:20:00Z',
          most_frequent: 'view'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'daily_routine', 'description' => 'Morning login', 'confidence' => 0.9 },
          { 'pattern_type' => 'burst', 'description' => 'Short burst', 'confidence' => 0.7 }
        ]
      end

      let(:user_score) { 80.5 }
      let(:anomalies) do
        [
          { 'type' => 'suspicious', 'timestamp' => '2025-01-01T10:30:00Z' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report with summary, timeline, patterns, and insights' do
        result = reporter.generate_report(user_id)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(now.iso8601)

        expect(result[:summary]).to include(
          total_actions: 2,
          unique_actions: 2,
          engagement_score: user_score,
          first_activity: '2025-01-01T10:15:00Z',
          last_activity: '2025-01-01T11:20:00Z'
        )

        expect(result[:action_breakdown]).to eq('login' => 1, 'view' => 1)

        expect(result[:patterns]).to contain_exactly(
          { type: 'daily_routine', description: 'Morning login', confidence: 0.9 },
          { type: 'burst', description: 'Short burst', confidence: 0.7 }
        )

        expect(result[:anomalies]).to eq(anomalies)

        expect(result[:timeline]).to eq([
          {
            period: '2025-01-01',
            total_actions: 2,
            actions: { 'login' => 1, 'view' => 1 },
            first_timestamp: '2025-01-01T10:15:00Z',
            last_timestamp: '2025-01-01T11:20:00Z'
          }
        ])

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(result[:insights].any? { |i| i.include?('Diverse activity profile') }).to be false
        expect(result[:insights].any? { |i| i.include?('Clear behavioral patterns') }).to be false
        expect(result[:insights].any? { |i| i.include?('Power user') }).to be false
      end

      it 'respects the group_by option for timeline aggregation by hour' do
        result = reporter.generate_report(user_id, group_by: :hour)
        expect(result[:timeline]).to eq([
          {
            period: '2025-01-01 10:00',
            total_actions: 1,
            actions: { 'login' => 1 },
            first_timestamp: '2025-01-01T10:15:00Z',
            last_timestamp: '2025-01-01T10:15:00Z'
          },
          {
            period: '2025-01-01 11:00',
            total_actions: 1,
            actions: { 'view' => 1 },
            first_timestamp: '2025-01-01T11:20:00Z',
            last_timestamp: '2025-01-01T11:20:00Z'
          }
        ])
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities are empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'groups by day by default' do
      let(:activities) do
        [
          { 'action' => 'open', 'timestamp' => '2025-01-01T10:00:00Z' },
          { 'action' => 'open', 'timestamp' => '2025-01-01T12:00:00Z' },
          { 'action' => 'close', 'timestamp' => '2025-01-02T09:00:00Z' }
        ]
      end

      it 'aggregates counts and sorts periods' do
        result = reporter.format_timeline(activities, :day)
        expect(result).to eq([
          {
            period: '2025-01-01',
            total_actions: 2,
            actions: { 'open' => 2 },
            first_timestamp: '2025-01-01T10:00:00Z',
            last_timestamp: '2025-01-01T12:00:00Z'
          },
          {
            period: '2025-01-02',
            total_actions: 1,
            actions: { 'close' => 1 },
            first_timestamp: '2025-01-02T09:00:00Z',
            last_timestamp: '2025-01-02T09:00:00Z'
          }
        ])
      end
    end

    context 'groups by week' do
      let(:activities) do
        [
          { 'action' => 'comment', 'timestamp' => '2025-01-06T10:00:00Z' }, # Monday
          { 'action' => 'comment', 'timestamp' => '2025-01-07T09:00:00Z' },
          { 'action' => 'like', 'timestamp' => '2025-01-13T08:00:00Z' }     # Next week
        ]
      end

      it 'aggregates into ISO week periods' do
        result = reporter.format_timeline(activities, :week)
        expect(result).to eq([
          {
            period: '2025-W02',
            total_actions: 2,
            actions: { 'comment' => 2 },
            first_timestamp: '2025-01-06T10:00:00Z',
            last_timestamp: '2025-01-07T09:00:00Z'
          },
          {
            period: '2025-W03',
            total_actions: 1,
            actions: { 'like' => 1 },
            first_timestamp: '2025-01-13T08:00:00Z',
            last_timestamp: '2025-01-13T08:00:00Z'
          }
        ])
      end
    end

    context 'groups by month' do
      let(:activities) do
        [
          { 'action' => 'upload', 'timestamp' => '2025-02-01T00:00:00Z' },
          { 'action' => 'upload', 'timestamp' => '2025-02-15T12:00:00Z' },
          { 'action' => 'download', 'timestamp' => '2025-03-01T00:00:00Z' }
        ]
      end

      it 'aggregates into monthly periods' do
        result = reporter.format_timeline(activities, :month)
        expect(result).to eq([
          {
            period: '2025-02',
            total_actions: 2,
            actions: { 'upload' => 2 },
            first_timestamp: '2025-02-01T00:00:00Z',
            last_timestamp: '2025-02-15T12:00:00Z'
          },
          {
            period: '2025-03',
            total_actions: 1,
            actions: { 'download' => 1 },
            first_timestamp: '2025-03-01T00:00:00Z',
            last_timestamp: '2025-03-01T00:00:00Z'
          }
        ])
      end
    end

    context 'groups by hour' do
      let(:activities) do
        [
          { 'action' => 'ping', 'timestamp' => '2025-01-01T10:05:00Z' },
          { 'action' => 'pong', 'timestamp' => '2025-01-01T10:59:00Z' },
          { 'action' => 'ping', 'timestamp' => '2025-01-01T11:01:00Z' }
        ]
      end

      it 'aggregates into hourly periods' do
        result = reporter.format_timeline(activities, :hour)
        expect(result).to eq([
          {
            period: '2025-01-01 10:00',
            total_actions: 2,
            actions: { 'ping' => 1, 'pong' => 1 },
            first_timestamp: '2025-01-01T10:05:00Z',
            last_timestamp: '2025-01-01T10:59:00Z'
          },
          {
            period: '2025-01-01 11:00',
            total_actions: 1,
            actions: { 'ping' => 1 },
            first_timestamp: '2025-01-01T11:01:00Z',
            last_timestamp: '2025-01-01T11:01:00Z'
          }
        ])
      end
    end

    context 'unknown grouping defaults to day' do
      let(:activities) do
        [
          { 'action' => 'a', 'timestamp' => '2025-01-01T00:00:00Z' },
          { 'action' => 'b', 'timestamp' => '2025-01-01T01:00:00Z' }
        ]
      end

      it 'falls back to daily aggregation' do
        result = reporter.format_timeline(activities, :unknown)
        expect(result).to eq([
          {
            period: '2025-01-01',
            total_actions: 2,
            actions: { 'a' => 1, 'b' => 1 },
            first_timestamp: '2025-01-01T00:00:00Z',
            last_timestamp: '2025-01-01T01:00:00Z'
          }
        ])
      end
    end

    context 'handles invalid timestamps by bucketing into current time period' do
      let(:fixed_now) { Time.utc(2025, 1, 3, 0, 0, 0) }

      before do
        allow(Time).to receive(:now).and_return(fixed_now)
      end

      let(:activities) do
        [
          { 'action' => 'ok', 'timestamp' => '2025-01-02T10:00:00Z' },
          { 'action' => 'bad', 'timestamp' => 'invalid-timestamp' }
        ]
      end

      it 'places invalid timestamps into the current day bucket' do
        result = reporter.format_timeline(activities, :day)
        expect(result).to eq([
          {
            period: '2025-01-02',
            total_actions: 1,
            actions: { 'ok' => 1 },
            first_timestamp: '2025-01-02T10:00:00Z',
            last_timestamp: '2025-01-02T10:00:00Z'
          },
          {
            period: '2025-01-03',
            total_actions: 1,
            actions: { 'bad' => 1 },
            first_timestamp: 'invalid-timestamp',
            last_timestamp: 'invalid-timestamp'
          }
        ])
      end
    end
  end

  describe '#export_to_json' do
    let(:report_hash) do
      {
        user_id: 'u1',
        summary: { total_actions: 3 },
        timeline: []
      }
    end

    context 'when a filepath is provided' do
      it 'writes the JSON and returns success with path and size' do
        Dir.mktmpdir do |dir|
          file = File.join(dir, 'report.json')
          result = reporter.export_to_json(report_hash, file)
          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(file)
          expect(result[:size]).to eq(JSON.pretty_generate(report_hash).bytesize)
          content = File.read(file)
          expect(content).to eq(JSON.pretty_generate(report_hash))
        end
      end
    end

    context 'when no filepath is provided' do
      it 'returns the JSON data in the response' do
        result = reporter.export_to_json(report_hash)
        expect(result[:success]).to be true
        expect(result[:data]).to eq(JSON.pretty_generate(report_hash))
      end
    end

    context 'when writing fails' do
      it 'returns an error payload' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        Dir.mktmpdir do |dir|
          file = File.join(dir, 'report.json')
          result = reporter.export_to_json(report_hash, file)
          expect(result[:success]).to be false
          expect(result[:error]).to eq('disk full')
        end
      end
    end }
  end

  describe '#compare_users' do
    context 'when fewer than 2 users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(now.iso8601)
      end
    end

    context 'with multiple users' do
      let(:user_ids) { ['u1', 'u2', 'u3'] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{ 'a' => 1 }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{ 'b' => 1 }, { 'b' => 2 }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([{ 'c' => 1 }])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 5, unique_actions: 2, action_counts: {}, first_activity: now.iso8601, last_activity: now.iso8601, most_frequent: 'click' })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 10, unique_actions: 3, action_counts: {}, first_activity: now.iso8601, last_activity: now.iso8601, most_frequent: 'view' })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 8, unique_actions: 2, action_counts: {}, first_activity: now.iso8601, last_activity: now.iso8601, most_frequent: 'like' })

        allow(reporter).to receive(:fetch_user_score).with([{ 'a' => 1 }]).and_return(60.1)
        allow(reporter).to receive(:fetch_user_score).with([{ 'b' => 1 }, { 'b' => 2 }]).and_return(80.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'c' => 1 }]).and_return(70.0)
      end

      it 'returns sorted comparisons, top user, and average score' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].length).to eq(3)

        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(['u2', 'u3', 'u1'])
        expect(result[:comparisons][0]).to include(user_id: 'u2', total_actions: 10, engagement_score: 80.0, most_frequent_action: 'view')
        expect(result[:comparisons][1]).to include(user_id: 'u3', total_actions: 8, engagement_score: 70.0, most_frequent_action: 'like')
        expect(result[:comparisons][2]).to include(user_id: 'u1', total_actions: 5, engagement_score: 60.1, most_frequent_action: 'click')

        expect(result[:top_user]).to eq('u2')
        expected_avg = ((80.0 + 70.0 + 60.1) / 3.0).round(2)
        expect(result[:average_score]).to eq(expected_avg)
      end
    end
  end
end
