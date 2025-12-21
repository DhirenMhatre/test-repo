require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  subject(:generator) do
    described_class.new
  end

  before do
    user_klass = Class.new
    stub_const('User', user_klass)
  end

  describe '#generate_user_report' do
    context 'with valid user ids' do
      let(:user1) do
        double('User', id: 1, name: 'Alice', posts: double('Posts', count: 2))
      end

      let(:user2) do
        double('User', id: 2, name: 'Bob', posts: double('Posts', count: 5))
      end

      before do
        allow(User).to receive(:find).with(1).and_return(user1)
        allow(User).to receive(:find).with(2).and_return(user2)
      end

      it 'queries each user and prints name with post count' do
        expect(User).to receive(:find).with(1)
        expect(User).to receive(:find).with(2)

        expect do
          generator.generate_user_report([1, 2])
        end.to output("Alice: 2 posts\nBob: 5 posts\n").to_stdout
      end
    end

    context 'with an empty array' do
      it 'does not query and prints nothing' do
        expect(User).not_to receive(:find)

        expect do
          generator.generate_user_report([])
        end.to output("").to_stdout
      end
    end

    context 'when user_ids is nil' do
      it 'raises NoMethodError' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when User.find raises an error' do
      before do
        allow(User).to receive(:find).with(999).and_raise(StandardError.new('not found'))
      end

      it 'propagates the error' do
        expect do
          generator.generate_user_report([999])
        end.to raise_error(StandardError, 'not found')
      end
    end
  end

  describe '#build_csv' do
    context 'with multiple records' do
      let(:records) do
        [
          double('Record', id: 1, name: 'A'),
          double('Record', id: 2, name: 'B')
        ]
      end

      it 'returns concatenated CSV lines' do
        result = generator.build_csv(records)
        expect(result).to eq("1,A\n2,B\n")
      end
    end

    context 'with an empty array' do
      it 'returns an empty string' do
        result = generator.build_csv([])
        expect(result).to eq("")
      end
    end

    context 'when records is nil' do
      it 'raises NoMethodError' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when a record is missing required attributes' do
      it 'raises NoMethodError' do
        records = [double('Record', id: 3)]
        expect do
          generator.build_csv(records)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping items and duplicates' do
      it 'returns all matches including duplicates' do
        list_a = [1, 2, 3]
        list_b = [2, 3, 4, 3]
        expect(generator.find_matches(list_a, list_b)).to eq([2, 3, 3])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        expect(generator.find_matches([1, 5], [2, 3, 4])).to eq([])
      end
    end

    context 'when one list is empty' do
      it 'returns an empty array for empty list_a' do
        expect(generator.find_matches([], [1, 2, 3])).to eq([])
      end

      it 'returns an empty array for empty list_b' do
        expect(generator.find_matches([1, 2, 3], [])).to eq([])
      end
    end

    context 'when list_a is nil' do
      it 'raises NoMethodError' do
        expect do
          generator.find_matches(nil, [1, 2])
        end.to raise_error(NoMethodError)
      end
    end

    context 'when list_b is nil' do
      it 'raises NoMethodError' do
        expect do
          generator.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    context 'when users exist' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'sends an email to each user' do
        expect(generator).to receive(:send_email).with(user1).ordered
        expect(generator).to receive(:send_email).with(user2).ordered
        generator.process_all_users
      end
    end

    context 'when there are no users' do
      before do
        allow(User).to receive(:all).and_return([])
      end

      it 'does not call send_email' do
        expect(generator).not_to receive(:send_email)
        generator.process_all_users
      end
    end

    context 'when fetching users raises an error' do
      before do
        allow(User).to receive(:all).and_raise(StandardError, 'db down')
      end

      it 'propagates the error' do
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'db down')
      end
    end

    context 'when send_email raises an error mid-iteration' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'propagates the error after processing earlier users' do
        calls = []
        allow(generator).to receive(:send_email) do |u|
          calls << u
          raise 'boom' if u == user2
        end

        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'boom')
        expect(calls).to eq([user1, user2])
      end
    end
  end
end
