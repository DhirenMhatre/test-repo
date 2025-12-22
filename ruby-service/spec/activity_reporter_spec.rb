require 'spec_helper'
require 'json'
require 'time'
require File.expand_path('../app/activity_reporter', __dir__)
require 'rails_helper'

RSpec.describe ActivityReporter do
  let(:reporter) { described_class.new }
  let(:fixed_now) { Time.parse('2023-01-01T12:00:00Z') }

  before do
    allow(Time).to receive(:now).and_return(fixed_now)
  end

  describe '#generate_report' do
    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('u-1').and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report('u-1')
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_now.iso8601)
      end
    end

    context 'with activities and all downstream data available' do
      let(:user_id) { 'user-1' }
      let(:activities) do
        [
          { 'timestamp' => '2023-01-01T09:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-01-01T10:30:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-01-02T11:00:00Z', 'action' => 'click' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 2,
          action_counts: { 'click' => 2, 'view' => 1 },
          first_activity: '2023-01-01T09:00:00Z',
          last_activity: '2023-01-02T11:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'burst', 'description' => 'Short bursts', 'confidence' => 0.8 },
          { 'pattern_type' => 'daily', 'description' => 'Daily login', 'confidence' => 0.9 },
          { 'pattern_type' => 'session', 'description' => 'Long sessions', 'confidence' => 0.7 }
        ]
      end

      let(:expected_patterns) do
        patterns_raw.map do |p|
          { type: p['pattern_type'], description: p['description'], confidence: p['confidence'] }
        end
      end

      let(:user_score) { 82.5 }
      let(:anomalies) { [{ 'id' => 1, 'reason' => 'spike' }] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report with summaries, patterns, anomalies, and insights' do
        result = reporter.generate_report(user_id, group_by: :day)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(fixed_now.iso8601)

        expect(result[:summary]).to include(
          total_actions: 3,
          unique_actions: 2,
          engagement_score: user_score,
          first_activity: '2023-01-01T09:00:00Z',
          last_activity: '2023-01-02T11:00:00Z'
        )

        expect(result[:action_breakdown]).to eq({ 'click' => 2, 'view' => 1 })
        expect(result[:patterns]).to eq(expected_patterns)
        expect(result[:anomalies]).to eq(anomalies)

        expect(result[:timeline]).to be_an(Array)
        expect(result[:timeline].map { |t| t[:period] }).to eq(%w[2023-01-01 2023-01-02])

        day1 = result[:timeline].find { |t| t[:period] == '2023-01-01' }
        day2 = result[:timeline].find { |t| t[:period] == '2023-01-02' }

        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq({ 'click' => 1, 'view' => 1 })
        expect(day1[:first_timestamp]).to eq('2023-01-01T09:00:00Z')
        expect(day1[:last_timestamp]).to eq('2023-01-01T10:30:00Z')

        expect(day2[:total_actions]).to eq(1)
        expect(day2[:actions]).to eq({ 'click' => 1 })
        expect(day2[:first_timestamp]).to eq('2023-01-02T11:00:00Z')
        expect(day2[:last_timestamp]).to eq('2023-01-02T11:00:00Z')

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(result[:insights]).not_to include('Power user - high volume of activities')
        expect(result[:insights]).not_to include('Diverse activity profile across multiple action types')
      end
    end
  end

  describe '#format_timeline' do
    context 'when there are no activities' do
      it 'returns an empty array' do
        result = reporter.format_timeline([])
        expect(result).to eq([])
      end
    end

    context 'grouped by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2023-01-01T12:30:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-01-01T11:15:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-01-01T11:45:00Z', 'action' => 'click' }
        ]
      end

      it 'aggregates counts per hour and sorts by period' do
        result = reporter.format_timeline(activities, :hour)
        expect(result.map { |r| r[:period] }).to eq(['2023-01-01 11:00', '2023-01-01 12:00'])

        hour11 = result.find { |r| r[:period] == '2023-01-01 11:00' }
        hour12 = result.find { |r| r[:period] == '2023-01-01 12:00' }

        expect(hour11[:total_actions]).to eq(2)
        expect(hour11[:actions]).to eq({ 'click' => 2 })
        expect(hour11[:first_timestamp]).to eq('2023-01-01T11:15:00Z')
        expect(hour11[:last_timestamp]).to eq('2023-01-01T11:45:00Z')

        expect(hour12[:total_actions]).to eq(1)
        expect(hour12[:actions]).to eq({ 'view' => 1 })
        expect(hour12[:first_timestamp]).to eq('2023-01-01T12:30:00Z')
        expect(hour12[:last_timestamp]).to eq('2023-01-01T12:30:00Z')
      end
    end

    context 'grouped by week and month' do
      let(:acts) do
        [
          { 'timestamp' => '2023-01-02T08:00:00Z', 'action' => 'a' }, # Monday
          { 'timestamp' => '2023-01-03T09:00:00Z', 'action' => 'b' },
          { 'timestamp' => '2023-01-09T10:00:00Z', 'action' => 'a' }  # Next Monday
        ]
      end

      it 'uses ISO week periods and sorts them' do
        expected_periods = acts.map { |a| Time.parse(a['timestamp']).strftime('%Y-W%V') }.uniq.sort
        result = reporter.format_timeline(acts, :week)
        expect(result.map { |r| r[:period] }).to eq(expected_periods)
      end

      it 'uses month periods' do
        result = reporter.format_timeline(acts, :month)
        expect(result.map { |r| r[:period] }.uniq).to eq(['2023-01'])
      end
    end

    context 'with unknown grouping option' do
      let(:acts) do
        [
          { 'timestamp' => '2023-02-10T12:00:00Z', 'action' => 'x' },
          { 'timestamp' => '2023-02-10T13:00:00Z', 'action' => 'y' }
        ]
      end

      it 'falls back to day grouping' do
        result = reporter.format_timeline(acts, :unknown)
        expect(result.size).to eq(1)
        expect(result.first[:period]).to eq('2023-02-10')
      end
    end

    context 'when a timestamp is invalid' do
      let(:invalid_acts) do
        [
          { 'timestamp' => 'invalid', 'action' => 'x' }
        ]
      end

      it 'falls back to Time.now for grouping' do
        result = reporter.format_timeline(invalid_acts, :day)
        expect(result.size).to eq(1)
        expect(result.first[:period]).to eq(fixed_now.strftime('%Y-%m-%d'))
        expect(result.first[:first_timestamp]).to eq('invalid')
        expect(result.first[:last_timestamp]).to eq('invalid')
      end
    end
  end

  describe '#export_to_json' do
    let(:report_hash) do
      {
        foo: 'bar',
        count: 2,
        nested: { a: 1, b: [1, 2, 3] }
      }
    end

    context 'when no filepath is provided' do
      it 'returns the JSON string in the result and does not write to file' do
        expect(File).not_to receive(:write)
        result = reporter.export_to_json(report_hash)
        expect(result[:success]).to be true
        parsed = JSON.parse(result[:data])
        expect(parsed).to eq(JSON.parse(JSON.pretty_generate(report_hash)))
      end
    end

    context 'when a filepath is provided' do
      let(:filepath) { '/tmp/report.json' }
      let(:json_data) { JSON.pretty_generate(report_hash) }

      it 'writes the JSON to the file and returns metadata' do
        expect(File).to receive(:write).with(filepath, json_data).and_return(json_data.bytesize)
        result = reporter.export_to_json(report_hash, filepath)
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(filepath)
        expect(result[:size]).to eq(json_data.bytesize)
      end
    end

    context 'when an error occurs during write' do
      let(:filepath) { '/tmp/report.json' }

      it 'returns an error payload' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        result = reporter.export_to_json({ a: 1 }, filepath)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_now.iso8601)
      end
    end

    context 'with multiple users' do
      let(:user_ids) { %w[u1 u2 u3] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{
                                                                                   'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'a'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([
                                                                                   {
                                                                                     'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'b'
                                                                                   }, { 'timestamp' => '2023-01-02T00:00:00Z', 'action' => 'b' }
                                                                                 ])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([
                                                                                   { 'timestamp' => '2023-01-01T00:00:00Z',
                                                                                     'action' => 'c' }, { 'timestamp' => '2023-01-02T00:00:00Z', 'action' => 'c' }, { 'timestamp' => '2023-01-03T00:00:00Z', 'action' => 'd' }
                                                                                 ])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 1, unique_actions: 1,
                                                                                  action_counts: { 'a' => 1 }, first_activity: '2023-01-01T00:00:00Z', last_activity: '2023-01-01T00:00:00Z', most_frequent: 'a' })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 2, unique_actions: 1,
                                                                                  action_counts: { 'b' => 2 }, first_activity: '2023-01-01T00:00:00Z', last_activity: '2023-01-02T00:00:00Z', most_frequent: 'b' })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 3, unique_actions: 2,
                                                                                  action_counts: { 'c' => 2, 'd' => 1 }, first_activity: '2023-01-01T00:00:00Z', last_activity: '2023-01-03T00:00:00Z', most_frequent: 'c' })

        allow(reporter).to receive(:fetch_user_score).with(array_including(hash_including('action' => 'a'))).and_return(40.0)
        allow(reporter).to receive(:fetch_user_score).with(array_including(hash_including('action' => 'b'))).and_return(75.5)
        allow(reporter).to receive(:fetch_user_score).with(array_including(hash_including('action' => 'c'))).and_return(90.25)
      end

      it 'returns sorted comparisons with top user and average score' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].size).to eq(3)

        scores = result[:comparisons].map { |c| c[:engagement_score] }
        expect(scores).to eq(scores.sort.reverse)

        expect(result[:comparisons].first[:user_id]).to eq('u3')
        expect(result[:comparisons].first[:most_frequent_action]).to eq('c')
        expect(result[:top_user]).to eq('u3')

        avg = ((40.0 + 75.5 + 90.25) / 3.0).round(2)
        expect(result[:average_score]).to eq(avg)
      end
    end
  end
end
