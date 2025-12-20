require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    context 'with valid user_ids' do
      it 'prints user names and post counts and returns the input array' do
        user_class = Class.new
        stub_const('User', user_class)
        user1 = double('User1', name: 'Alice', posts: double('Posts1', count: 2))
        user2 = double('User2', name: 'Bob', posts: double('Posts2', count: 3))
        expect(User).to receive(:find).with(1).and_return(user1)
        expect(User).to receive(:find).with(2).and_return(user2)

        expect do
          result = generator.generate_user_report([1, 2])
          expect(result).to eq([1, 2])
        end.to output("Alice: 2 posts\nBob: 3 posts\n").to_stdout
      end
    end

    context 'with empty array' do
      it 'prints nothing and returns empty array' do
        user_class = Class.new
        stub_const('User', user_class)
        expect(User).not_to receive(:find)

        expect do
          result = generator.generate_user_report([])
          expect(result).to eq([])
        end.to output('').to_stdout
      end
    end

    context 'when User.find raises an error' do
      it 'propagates the error' do
        user_class = Class.new
        stub_const('User', user_class)
        allow(User).to receive(:find).and_raise(StandardError, 'boom')

        expect do
          generator.generate_user_report([42])
        end.to raise_error(StandardError, 'boom')
      end
    end

    context 'with nil input' do
      it 'raises NoMethodError' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    context 'with records having id and name' do
      it 'returns a CSV string with one line per record' do
        records = [
          double('Record1', id: 1, name: 'A'),
          double('Record2', id: 2, name: 'B')
        ]
        result = generator.build_csv(records)
        expect(result).to eq("1,A\n2,B\n")
      end
    end

    context 'with empty records' do
      it 'returns an empty string' do
        result = generator.build_csv([])
        expect(result).to eq('')
      end
    end

    context 'with nil records' do
      it 'raises NoMethodError' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping lists and duplicates' do
      it 'returns each match for every equal pair' do
        list_a = [1, 2, 2, 3]
        list_b = [2, 2, 4]
        expect(generator.find_matches(list_a, list_b)).to eq([2, 2, 2, 2])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        expect(generator.find_matches([1, 2], [3, 4])).to eq([])
      end
    end

    context 'with empty inputs' do
      it 'returns empty array when list_a is empty' do
        expect(generator.find_matches([], [1, 2])).to eq([])
      end

      it 'returns empty array when list_b is empty' do
        expect(generator.find_matches([1, 2], [])).to eq([])
      end
    end

    context 'with nil inputs' do
      it 'raises NoMethodError for nil list_a' do
        expect do
          generator.find_matches(nil, [])
        end.to raise_error(NoMethodError)
      end

      it 'raises NoMethodError for nil list_b' do
        expect do
          generator.find_matches([], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    context 'when users exist' do
      it 'sends email to each user returned by User.all' do
        user_class = Class.new
        stub_const('User', user_class)
        users = [double('U1'), double('U2'), double('U3')]
        allow(User).to receive(:all).and_return(users)
        expect(generator).to receive(:send_email).with(users[0]).ordered
        expect(generator).to receive(:send_email).with(users[1]).ordered
        expect(generator).to receive(:send_email).with(users[2]).ordered

        generator.process_all_users
      end
    end

    context 'when no users' do
      it 'does not call send_email' do
        user_class = Class.new
        stub_const('User', user_class)
        allow(User).to receive(:all).and_return([])
        expect(generator).not_to receive(:send_email)

        generator.process_all_users
      end
    end

    context 'when User.all returns nil' do
      it 'raises NoMethodError' do
        user_class = Class.new
        stub_const('User', user_class)
        allow(User).to receive(:all).and_return(nil)

        expect do
          generator.process_all_users
        end.to raise_error(NoMethodError)
      end
    end

    context 'when send_email raises' do
      it 'propagates the error' do
        user_class = Class.new
        stub_const('User', user_class)
        users = [double('U1')]
        allow(User).to receive(:all).and_return(users)
        allow(generator).to receive(:send_email).and_raise(RuntimeError, 'send failure')

        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'send failure')
      end
    end
  end
end
