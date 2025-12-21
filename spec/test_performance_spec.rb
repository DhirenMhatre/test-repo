require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    before do
      stub_const('User', Class.new)
    end

    let(:posts_double) do
      instance_double('PostsAssociation', count: 3)
    end

    let(:user_double) do
      instance_double('User', name: 'Alice', posts: posts_double)
    end

    context 'with valid user IDs' do
      let(:user_ids) do
        [1, 2]
      end

      before do
        allow(User).to receive(:find).with(1).and_return(user_double)
        allow(User).to receive(:find).with(2).and_return(user_double)
      end

      it 'finds each user, reads posts, and outputs a line per user' do
        expected_output = "Alice: 3 posts\nAlice: 3 posts\n"
        expect do
          result = generator.generate_user_report(user_ids)
          expect(result).to eq(user_ids)
        end.to output(expected_output).to_stdout
      end
    end

    context 'with an empty list' do
      let(:user_ids) do
        []
      end

      it 'does not query and returns the original array' do
        expect(User).not_to receive(:find)
        expect do
          result = generator.generate_user_report(user_ids)
          expect(result).to eq([])
        end.to output("").to_stdout
      end
    end

    context 'when User.find raises an error' do
      it 'propagates the exception' do
        allow(User).to receive(:find).and_raise(StandardError, 'not found')
        expect do
          generator.generate_user_report([123])
        end.to raise_error(StandardError, 'not found')
      end
    end

    context 'when user_ids is nil' do
      it 'raises NoMethodError' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    context 'with multiple records' do
      let(:records) do
        [
          double('Record', id: 1, name: 'Alice'),
          double('Record', id: 2, name: 'Bob')
        ]
      end

      it 'builds a CSV string using concatenation' do
        result = generator.build_csv(records)
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with an empty list' do
      it 'returns an empty string' do
        result = generator.build_csv([])
        expect(result).to eq("")
      end
    end

    context 'with nil fields on records' do
      it 'converts nils to empty strings in the CSV' do
        records = [double('Record', id: nil, name: nil)]
        result = generator.build_csv(records)
        expect(result).to eq(",\n")
      end
    end

    context 'when records is nil' do
      it 'raises NoMethodError' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'when matches include duplicates in list_b' do
      it 'returns duplicates accordingly' do
        list_a = [1, 2, 3]
        list_b = [3, 3, 2, 4]
        result = generator.find_matches(list_a, list_b)
        expect(result).to eq([2, 3, 3])
      end
    end

    context 'when there are no matches' do
      it 'returns an empty array' do
        result = generator.find_matches([1, 5], [2, 3, 4])
        expect(result).to eq([])
      end
    end

    context 'with an empty list_a' do
      it 'returns an empty array' do
        result = generator.find_matches([], [1, 2, 3])
        expect(result).to eq([])
      end
    end

    context 'with an empty list_b' do
      it 'returns an empty array' do
        result = generator.find_matches([1, 2, 3], [])
        expect(result).to eq([])
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
    before do
      stub_const('User', Class.new)
    end

    context 'with users present' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'calls send_email for each user in order' do
        expect(generator).to receive(:send_email).with(user1).ordered
        expect(generator).to receive(:send_email).with(user2).ordered
        result = generator.process_all_users
        expect(result).to eq([user1, user2])
      end
    end

    context 'with no users' do
      before do
        allow(User).to receive(:all).and_return([])
      end

      it 'does not call send_email and returns an empty array' do
        expect(generator).not_to receive(:send_email)
        result = generator.process_all_users
        expect(result).to eq([])
      end
    end

    context 'when send_email raises for a user' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'propagates the error and stops processing' do
        expect(generator).to receive(:send_email).with(user1).ordered.and_return(nil)
        expect(generator).to receive(:send_email).with(user2).ordered.and_raise(RuntimeError, 'boom')
        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'boom')
      end
    end
  end
end
