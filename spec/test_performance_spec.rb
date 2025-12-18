require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    before do
      stub_const('User', class_double('User'))
    end

    context 'with multiple user ids' do
      let(:user_ids) do
        [1, 2]
      end

      let(:posts1) do
        double('Posts')
      end

      let(:posts2) do
        double('Posts')
      end

      let(:user1) do
        double('User', name: 'Alice', posts: posts1)
      end

      let(:user2) do
        double('User', name: 'Bob', posts: posts2)
      end

      before do
        allow(posts1).to receive(:count).and_return(3)
        allow(posts2).to receive(:count).and_return(5)
        allow(User).to receive(:find).with(1).and_return(user1)
        allow(User).to receive(:find).with(2).and_return(user2)
      end

      it 'queries each user and prints name with posts count' do
        expect do
          generator.generate_user_report(user_ids)
        end.to output("Alice: 3 posts\nBob: 5 posts\n").to_stdout
        expect(User).to have_received(:find).with(1)
        expect(User).to have_received(:find).with(2)
        expect(posts1).to have_received(:count)
        expect(posts2).to have_received(:count)
      end
    end

    context 'with an empty list' do
      it 'prints nothing and does not query' do
        expect(User).not_to receive(:find)
        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout
      end
    end

    context 'when a user lookup raises an error' do
      it 'propagates the error' do
        allow(User).to receive(:find).with(99).and_raise(StandardError, 'user not found')
        expect do
          generator.generate_user_report([99])
        end.to raise_error(StandardError, 'user not found')
      end
    end
  end

  describe '#build_csv' do
    let(:record1) do
      double('Record', id: 1, name: 'Alice')
    end

    let(:record2) do
      double('Record', id: 2, name: 'Bob')
    end

    context 'with multiple records' do
      let(:records) do
        [record1, record2]
      end

      it 'concatenates id and name per line' do
        result = generator.build_csv(records)
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with an empty array' do
      it 'returns an empty string' do
        result = generator.build_csv([])
        expect(result).to eq('')
      end
    end

    context 'with nil input' do
      it 'raises an error' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping lists' do
      it 'returns the intersection preserving duplicates due to nested loops' do
        list_a = [1, 1]
        list_b = [1, 1]
        result = generator.find_matches(list_a, list_b)
        expect(result).to eq([1, 1, 1, 1])
      end
    end

    context 'with disjoint lists' do
      it 'returns an empty array' do
        result = generator.find_matches([1, 2], [3, 4])
        expect(result).to eq([])
      end
    end

    context 'with nil values present' do
      it 'matches nils correctly' do
        result = generator.find_matches([nil, 1], [nil, 2])
        expect(result).to eq([nil])
      end
    end

    context 'with empty inputs' do
      it 'returns an empty array when list_a is empty' do
        result = generator.find_matches([], [1, 2, 3])
        expect(result).to eq([])
      end

      it 'returns an empty array when list_b is empty' do
        result = generator.find_matches([1, 2, 3], [])
        expect(result).to eq([])
      end
    end

    context 'with invalid input' do
      it 'raises when list_a is nil' do
        expect do
          generator.find_matches(nil, [1])
        end.to raise_error(NoMethodError)
      end

      it 'raises when list_b is nil' do
        expect do
          generator.find_matches([1], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    before do
      stub_const('User', class_double('User'))
    end

    context 'with users returned from User.all' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email)
      end

      it 'calls send_email for each user' do
        generator.process_all_users
        expect(User).to have_received(:all)
        expect(generator).to have_received(:send_email).with(user1)
        expect(generator).to have_received(:send_email).with(user2)
      end
    end

    context 'when no users are returned' do
      before do
        allow(User).to receive(:all).and_return([])
        allow(generator).to receive(:send_email)
      end

      it 'does not call send_email' do
        generator.process_all_users
        expect(User).to have_received(:all)
        expect(generator).not_to have_received(:send_email)
      end
    end

    context 'when User.all raises an error' do
      before do
        allow(User).to receive(:all).and_raise('db error')
      end

      it 'propagates the error' do
        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'db error')
      end
    end

    context 'when send_email raises an error' do
      let(:user1) do
        double('User1')
      end

      before do
        allow(User).to receive(:all).and_return([user1])
        allow(generator).to receive(:send_email).with(user1).and_raise('send failed')
      end

      it 'propagates the error' do
        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'send failed')
      end
    end
  end
end
