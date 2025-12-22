require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  subject(:generator) do
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
      double('UserInstance', name: 'Alice', posts: posts1)
    end

    let(:user2) do
      double('UserInstance', name: 'Bob', posts: posts2)
    end

    before do
      user_class = Class.new
      stub_const('User', user_class)
    end

    context 'with valid user IDs' do
      it 'queries each user, counts posts, and prints the report lines' do
        expect(User).to receive(:find).with(1).and_return(user1)
        expect(User).to receive(:find).with(2).and_return(user2)
        expect(posts1).to receive(:count).and_return(3)
        expect(posts2).to receive(:count).and_return(0)

        expect do
          generator.generate_user_report(user_ids)
        end.to output("Alice: 3 posts\nBob: 0 posts\n").to_stdout
      end

      it 'returns nil after printing output' do
        allow(User).to receive(:find) do |id|
          id == 1 ? user1 : user2
        end
        allow(posts1).to receive(:count).and_return(3)
        allow(posts2).to receive(:count).and_return(0)

        result = nil
        expect do
          result = generator.generate_user_report(user_ids)
        end.to output("Alice: 3 posts\nBob: 0 posts\n").to_stdout
        expect(result).to be_nil
      end
    end

    context 'when user_ids is empty' do
      it 'does not query users and prints nothing' do
        expect(User).not_to receive(:find)

        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout
      end
    end

    context 'when User.find raises an error' do
      it 'propagates the error' do
        expect(User).to receive(:find).with(1).and_raise(StandardError, 'DB error')

        expect do
          generator.generate_user_report([1])
        end.to raise_error(StandardError, 'DB error')
      end
    end

    context 'with nil input' do
      it 'raises a NoMethodError' do
        expect do
          generator.generate_user_report(nil)
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

    context 'with valid records' do
      it 'returns a CSV string with id and name per line' do
        csv = generator.build_csv([record1, record2])
        expect(csv).to eq("1,Alpha\n2,Beta\n")
      end

      it 'includes empty name values when name is nil' do
        record = double('Record', id: 3, name: nil)
        csv = generator.build_csv([record])
        expect(csv).to eq("3,\n")
      end
    end

    context 'with empty records' do
      it 'returns an empty string' do
        csv = generator.build_csv([])
        expect(csv).to eq('')
      end
    end

    context 'with nil input' do
      it 'raises a NoMethodError' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping elements' do
      it 'returns matches accounting for duplicates based on nested loop behavior' do
        list_a = [1, 2, 2, 3]
        list_b = [2, 2, 3, 3]
        matches = generator.find_matches(list_a, list_b)
        expect(matches).to eq([2, 2, 2, 2, 3, 3])
      end

      it 'uses == for equality comparison' do
        list_a = %w[1 2 x]
        list_b = %w[2 3 x x]
        expect(generator.find_matches(list_a, list_b)).to eq(%w[2 x x])
      end
    end

    context 'with non-overlapping elements' do
      it 'returns an empty array' do
        expect(generator.find_matches([1, 4], [2, 3])).to eq([])
      end
    end

    context 'with empty inputs' do
      it 'returns empty when list_a is empty' do
        expect(generator.find_matches([], [1, 2, 3])).to eq([])
      end

      it 'returns empty when list_b is empty' do
        expect(generator.find_matches([1, 2, 3], [])).to eq([])
      end
    end

    context 'with nil inputs' do
      it 'raises NoMethodError when list_a is nil' do
        expect do
          generator.find_matches(nil, [1])
        end.to raise_error(NoMethodError)
      end

      it 'raises NoMethodError when list_b is nil' do
        expect do
          generator.find_matches([1], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:user1) do
      double('UserInstance1')
    end

    let(:user2) do
      double('UserInstance2')
    end

    before do
      user_class = Class.new
      stub_const('User', user_class)
    end

    context 'when users are present' do
      before do
        allow(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email)
      end

      it 'calls send_email for each user' do
        expect(generator).to receive(:send_email).with(user1).once
        expect(generator).to receive(:send_email).with(user2).once
        generator.process_all_users
      end

      it 'returns the collection from each' do
        result = generator.process_all_users
        expect(result).to eq([user1, user2])
      end
    end

    context 'when there are no users' do
      it 'does not call send_email and returns empty collection' do
        allow(User).to receive(:all).and_return([])
        expect(generator).not_to receive(:send_email)
        result = generator.process_all_users
        expect(result).to eq([])
      end
    end

    context 'when User.all raises an error' do
      it 'propagates the error' do
        allow(User).to receive(:all).and_raise(StandardError, 'DB read failure')
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'DB read failure')
      end
    end

    context 'when sending email fails' do
      it 'propagates the error from send_email' do
        allow(User).to receive(:all).and_return([user1])
        allow(generator).to receive(:send_email).and_raise(RuntimeError, 'SMTP error')
        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'SMTP error')
      end
    end
  end
end
