require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  describe '#generate_user_report' do
    let(:instance) { described_class.new }

    context 'with valid user ids' do
      let(:posts1) { double('PostsAssociation', count: 3) }
      let(:posts2) { double('PostsAssociation', count: 5) }
      let(:user1) { double('UserInstance', name: 'Alice', posts: posts1) }
      let(:user2) { double('UserInstance', name: 'Bob', posts: posts2) }

      before do
        stub_const('User', Class.new)
        allow(User).to receive(:find).with(1).and_return(user1)
        allow(User).to receive(:find).with(2).and_return(user2)
      end

      it 'queries each id and outputs a line per user with post counts' do
        expect do
          instance.generate_user_report([1, 2])
        end.to output("Alice: 3 posts\nBob: 5 posts\n").to_stdout
      end
    end

    context 'when user_ids is empty' do
      before do
        stub_const('User', Class.new)
      end

      it 'outputs nothing' do
        expect do
          instance.generate_user_report([])
        end.to output('').to_stdout
      end
    end

    context 'when a lookup fails' do
      before do
        stub_const('User', Class.new)
        allow(User).to receive(:find).with(99).and_raise(RuntimeError, 'not found')
      end

      it 'propagates the error' do
        expect do
          instance.generate_user_report([99])
        end.to raise_error(RuntimeError, 'not found')
      end
    end

    context 'when user_ids is nil' do
      it 'raises NoMethodError' do
        expect do
          instance.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:instance) { described_class.new }
    let(:record1) { double('Record', id: 1, name: 'Alice') }
    let(:record2) { double('Record', id: 2, name: 'Bob') }

    context 'with multiple records' do
      it 'returns a CSV string with one line per record' do
        result = instance.build_csv([record1, record2])
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with empty records array' do
      it 'returns an empty string' do
        expect(instance.build_csv([])).to eq('')
      end
    end

    context 'with nil input' do
      it 'raises NoMethodError' do
        expect do
          instance.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when a record lacks required methods' do
      let(:bad_record) { double('BadRecord', name: 'NoID') }

      it 'raises NoMethodError if id is missing' do
        expect do
          instance.build_csv([bad_record])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    let(:instance) { described_class.new }

    context 'when both lists have shared elements' do
      it 'returns elements present in both lists' do
        expect(instance.find_matches([1, 2, 3], [2, 3, 4])).to eq([2, 3])
      end
    end

    context 'when list_b contains duplicates' do
      it 'includes duplicates for each matching occurrence' do
        expect(instance.find_matches([2], [1, 2, 2, 3])).to eq([2, 2])
      end
    end

    context 'when order differs between lists' do
      it 'preserves the nested loop order (list_a outer, list_b inner)' do
        expect(instance.find_matches([3, 1, 2], [2, 1, 3])).to eq([3, 1, 2])
      end
    end

    context 'with empty lists' do
      it 'returns an empty array when both are empty' do
        expect(instance.find_matches([], [])).to eq([])
      end

      it 'returns an empty array when one is empty' do
        expect(instance.find_matches([1, 2], [])).to eq([])
      end
    end

    context 'with nil inputs' do
      it 'raises NoMethodError when list_a is nil' do
        expect do
          instance.find_matches(nil, [1, 2])
        end.to raise_error(NoMethodError)
      end

      it 'raises NoMethodError when list_b is nil' do
        expect do
          instance.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:instance) { described_class.new }

    context 'when there are users to process' do
      let(:user1) { double('UserInstance1') }
      let(:user2) { double('UserInstance2') }
      let(:user3) { double('UserInstance3') }

      before do
        stub_const('User', Class.new)
        allow(User).to receive(:all).and_return([user1, user2, user3])
      end

      it 'calls send_email on each user' do
        expect(instance).to receive(:send_email).with(user1)
        expect(instance).to receive(:send_email).with(user2)
        expect(instance).to receive(:send_email).with(user3)
        instance.process_all_users
      end
    end

    context 'when there are no users' do
      before do
        stub_const('User', Class.new)
        allow(User).to receive(:all).and_return([])
      end

      it 'does not call send_email' do
        expect(instance).not_to receive(:send_email)
        instance.process_all_users
      end
    end

    context 'when sending email raises an error' do
      let(:user1) { double('UserInstance1') }
      let(:user2) { double('UserInstance2') }
      let(:user3) { double('UserInstance3') }

      before do
        stub_const('User', Class.new)
        allow(User).to receive(:all).and_return([user1, user2, user3])
        allow(instance).to receive(:send_email).with(user1).and_return(nil)
        allow(instance).to receive(:send_email).with(user2).and_raise(RuntimeError, 'boom')
        allow(instance).to receive(:send_email).with(user3).and_return(nil)
      end

      it 'propagates the error and may stop processing subsequent users' do
        expect(instance).not_to receive(:send_email).with(user3)
        expect do
          instance.process_all_users
        end.to raise_error(RuntimeError, 'boom')
      end
    end
  end
end
