require 'spec_helper'
require 'rails_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:report_generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    let(:user_ids) do
      [1, 2, 3]
    end

    let(:user_double_1) do
      instance_double('User', name: 'Alice', posts: posts_double_1)
    end

    let(:user_double_2) do
      instance_double('User', name: 'Bob', posts: posts_double_2)
    end

    let(:user_double_3) do
      instance_double('User', name: 'Carol', posts: posts_double_3)
    end

    let(:posts_double_1) do
      instance_double('ActiveRecord::Relation', count: 5)
    end

    let(:posts_double_2) do
      instance_double('ActiveRecord::Relation', count: 2)
    end

    let(:posts_double_3) do
      instance_double('ActiveRecord::Relation', count: 0)
    end

    before do
      stub_const('User', Class.new)

      allow(User).to receive(:find).with(1).and_return(user_double_1)
      allow(User).to receive(:find).with(2).and_return(user_double_2)
      allow(User).to receive(:find).with(3).and_return(user_double_3)
    end

    context 'with valid user ids' do
      it 'queries each user and their posts and prints the report lines' do
        expect(User).to receive(:find).with(1).ordered.and_return(user_double_1)
        expect(User).to receive(:find).with(2).ordered.and_return(user_double_2)
        expect(User).to receive(:find).with(3).ordered.and_return(user_double_3)

        expect(posts_double_1).to receive(:count).and_return(5)
        expect(posts_double_2).to receive(:count).and_return(2)
        expect(posts_double_3).to receive(:count).and_return(0)

        expect do
          report_generator.generate_user_report(user_ids)
        end.to output("Alice: 5 posts\nBob: 2 posts\nCarol: 0 posts\n").to_stdout
      end
    end

    context 'with an empty array of user ids' do
      let(:user_ids) do
        []
      end

      it 'does not query any users and prints nothing' do
        expect(User).not_to receive(:find)

        expect do
          report_generator.generate_user_report(user_ids)
        end.to output('').to_stdout
      end
    end

    context 'when a user id lookup raises an error' do
      let(:user_ids) do
        [1]
      end

      before do
        allow(User).to receive(:find).with(1).and_raise(StandardError, 'DB error')
      end

      it 'propagates the error' do
        expect do
          report_generator.generate_user_report(user_ids)
        end.to raise_error(StandardError, 'DB error')
      end
    end

    context 'when user_ids is nil' do
      let(:user_ids) do
        nil
      end

      it 'raises a NoMethodError because nil does not respond to each' do
        expect do
          report_generator.generate_user_report(user_ids)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:records) do
      [
        instance_double('Record', id: 1, name: 'Alice'),
        instance_double('Record', id: 2, name: 'Bob')
      ]
    end

    context 'with valid records' do
      it 'builds a CSV string with one line per record' do
        result = report_generator.build_csv(records)
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with an empty records array' do
      let(:records) do
        []
      end

      it 'returns an empty string' do
        result = report_generator.build_csv(records)
        expect(result).to eq('')
      end
    end

    context 'with a single record' do
      let(:records) do
        [
          instance_double('Record', id: 10, name: 'Single')
        ]
      end

      it 'returns CSV with only that record' do
        result = report_generator.build_csv(records)
        expect(result).to eq("10,Single\n")
      end
    end

    context 'when a record does not respond to id or name' do
      let(:bad_record) do
        Object.new
      end

      let(:records) do
        [bad_record]
      end

      it 'raises a NoMethodError' do
        expect do
          report_generator.build_csv(records)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when records is nil' do
      let(:records) do
        nil
      end

      it 'raises a NoMethodError because nil does not respond to each' do
        expect do
          report_generator.build_csv(records)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    let(:list_a) do
      [1, 2, 3, 2]
    end

    let(:list_b) do
      [2, 3, 4]
    end

    context 'with overlapping elements' do
      it 'returns all matches including duplicates based on nested loops' do
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to eq([2, 3, 2])
      end
    end

    context 'with no overlapping elements' do
      let(:list_a) do
        [1, 5]
      end

      let(:list_b) do
        [2, 3, 4]
      end

      it 'returns an empty array' do
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to eq([])
      end
    end

    context 'when one list is empty' do
      let(:list_a) do
        []
      end

      it 'returns an empty array when list_a is empty' do
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to eq([])
      end

      context 'and list_b is also empty' do
        let(:list_b) do
          []
        end

        it 'returns an empty array' do
          result = report_generator.find_matches(list_a, list_b)
          expect(result).to eq([])
        end
      end
    end

    context 'when list_a is nil' do
      let(:list_a) do
        nil
      end

      it 'raises a NoMethodError because nil does not respond to each' do
        expect do
          report_generator.find_matches(list_a, list_b)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when list_b is nil' do
      let(:list_b) do
        nil
      end

      it 'raises a NoMethodError because nil does not respond to each' do
        expect do
          report_generator.find_matches(list_a, list_b)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:user_1) do
      instance_double('User', email: 'user1@example.com')
    end

    let(:user_2) do
      instance_double('User', email: 'user2@example.com')
    end

    let(:users_relation) do
      [user_1, user_2]
    end

    before do
      stub_const('User', Class.new)
      allow(User).to receive(:all).and_return(users_relation)
    end

    context 'with users present' do
      it 'iterates over all users and calls send_email for each' do
        expect(User).to receive(:all).and_return(users_relation)

        expect(report_generator).to receive(:send_email).with(user_1).ordered
        expect(report_generator).to receive(:send_email).with(user_2).ordered

        report_generator.process_all_users
      end
    end

    context 'when there are no users' do
      let(:users_relation) do
        []
      end

      it 'does not call send_email' do
        expect(User).to receive(:all).and_return(users_relation)
        expect(report_generator).not_to receive(:send_email)

        report_generator.process_all_users
      end
    end

    context 'when User.all raises an error' do
      before do
        allow(User).to receive(:all).and_raise(StandardError, 'DB error')
      end

      it 'propagates the error' do
        expect do
          report_generator.process_all_users
        end.to raise_error(StandardError, 'DB error')
      end
    end

    context 'when send_email raises an error for a user' do
      before do
        allow(report_generator).to receive(:send_email).with(user_1).and_raise(StandardError, 'Email error')
        allow(report_generator).to receive(:send_email).with(user_2)
      end

      it 'propagates the error and stops processing further users' do
        expect do
          report_generator.process_all_users
        end.to raise_error(StandardError, 'Email error')
      end
    end
  end
end
