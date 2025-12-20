require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:reporter) do
    described_class.new
  end

  describe '#generate_user_report' do
    let(:user_ids) do
      [1, 2]
    end

    let(:posts1) do
      double('Posts', count: 3)
    end

    let(:posts2) do
      double('Posts', count: 0)
    end

    let(:user1) do
      double('User', name: 'Alice', posts: posts1)
    end

    let(:user2) do
      double('User', name: 'Bob', posts: posts2)
    end

    before do
      stub_const('User', Class.new)
      allow(User).to receive(:find).with(1).and_return(user1)
      allow(User).to receive(:find).with(2).and_return(user2)
    end

    it 'queries each user and prints name with post counts, returning the original ids' do
      expect(User).to receive(:find).with(1).ordered.and_return(user1)
      expect(User).to receive(:find).with(2).ordered.and_return(user2)
      expect(posts1).to receive(:count).and_return(3)
      expect(posts2).to receive(:count).and_return(0)
      expected_output = "Alice: 3 posts\nBob: 0 posts\n"
      expect do
        result = reporter.generate_user_report(user_ids)
        expect(result).to eq(user_ids)
      end.to output(expected_output).to_stdout
    end

    context 'with empty user_ids' do
      let(:user_ids) do
        []
      end

      it 'prints nothing and returns an empty array' do
        expect(User).not_to receive(:find)
        expect do
          result = reporter.generate_user_report(user_ids)
          expect(result).to eq([])
        end.to output('').to_stdout
      end
    end

    context 'when a user lookup raises an error' do
      it 'propagates the error without printing' do
        allow(User).to receive(:find).with(1).and_raise(StandardError, 'DB error')
        expect do
          reporter.generate_user_report([1])
        end.to raise_error(StandardError, 'DB error')
      end
    end

    context 'when a user has no posts method' do
      it 'raises NoMethodError' do
        broken_user = double('User', name: 'Eve')
        allow(User).to receive(:find).with(42).and_return(broken_user)
        expect do
          reporter.generate_user_report([42])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:record1) do
      double('Record', id: 1, name: 'Alpha')
    end

    let(:record2) do
      double('Record', id: 2, name: 'Beta')
    end

    it 'concatenates rows into a CSV-like string' do
      result = reporter.build_csv([record1, record2])
      expect(result).to eq("1,Alpha\n2,Beta\n")
    end

    it 'returns an empty string for empty input' do
      result = reporter.build_csv([])
      expect(result).to eq('')
    end

    it 'raises an error when records is nil' do
      expect do
        reporter.build_csv(nil)
      end.to raise_error(NoMethodError)
    end

    it 'handles names containing commas without escaping' do
      rec = double('Record', id: 3, name: 'Hello,World')
      result = reporter.build_csv([rec])
      expect(result).to eq("3,Hello,World\n")
    end
  end

  describe '#find_matches' do
    it 'returns items present in both lists, including duplicates' do
      list_a = [1, 2, 2, 3]
      list_b = [2, 2, 4]
      result = reporter.find_matches(list_a, list_b)
      expect(result).to eq([2, 2, 2, 2])
    end

    it 'returns an empty array when there are no matches' do
      result = reporter.find_matches([1, 3], [2, 4])
      expect(result).to eq([])
    end

    it 'handles empty inputs' do
      expect(reporter.find_matches([], [])).to eq([])
      expect(reporter.find_matches([1], [])).to eq([])
      expect(reporter.find_matches([], [1])).to eq([])
    end

    it 'raises when the second list is nil' do
      expect do
        reporter.find_matches([1], nil)
      end.to raise_error(NoMethodError)
    end
  end

  describe '#process_all_users' do
    let(:user1) do
      double('User', id: 1)
    end

    let(:user2) do
      double('User', id: 2)
    end

    before do
      stub_const('User', Class.new)
      allow(User).to receive(:all).and_return([user1, user2])
      allow(reporter).to receive(:send_email)
    end

    it 'iterates over all users and sends an email to each' do
      expect(User).to receive(:all).and_return([user1, user2])
      expect(reporter).to receive(:send_email).with(user1).ordered
      expect(reporter).to receive(:send_email).with(user2).ordered
      reporter.process_all_users
    end

    it 'does nothing when there are no users' do
      allow(User).to receive(:all).and_return([])
      expect(reporter).not_to receive(:send_email)
      reporter.process_all_users
    end

    it 'propagates errors from User.all' do
      allow(User).to receive(:all).and_raise(StandardError, 'boom')
      expect do
        reporter.process_all_users
      end.to raise_error(StandardError, 'boom')
    end

    it 'propagates errors raised during send_email' do
      allow(reporter).to receive(:send_email).with(user1).and_raise(StandardError, 'smtp error')
      expect do
        reporter.process_all_users
      end.to raise_error(StandardError, 'smtp error')
    end
  end
end
