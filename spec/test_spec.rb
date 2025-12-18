require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) { 'Alice' }
      let(:user) { described_class.new(name) }

      it 'sets @name to the given value' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:user) { described_class.new(nil) }

      it 'allows nil name' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'with empty string name' do
      let(:user) { described_class.new('') }

      it 'stores empty string' do
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('Alice') }
    let(:db_double) { double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'with integer id' do
      let(:id) { 42 }
      let(:query) { 'SELECT * FROM users WHERE id = 42' }

      it 'executes the expected SQL and returns the result' do
        allow(db_double).to receive(:execute).with(query).and_return(['row'])
        expect(user.find_user(id)).to eq(['row'])
        expect(db_double).to have_received(:execute).with(query).once
      end
    end

    context 'with string id containing SQL content' do
      let(:id) { '1 OR 1=1' }
      let(:query) { 'SELECT * FROM users WHERE id = 1 OR 1=1' }

      it 'passes the interpolated SQL to DB.execute' do
        allow(db_double).to receive(:execute).with(query).and_return(['all_rows'])
        expect(user.find_user(id)).to eq(['all_rows'])
        expect(db_double).to have_received(:execute).with(query).once
      end
    end

    context 'with nil id' do
      let(:id) { nil }
      let(:query) { 'SELECT * FROM users WHERE id = ' }

      it 'interpolates nil to an empty string and calls DB.execute' do
        allow(db_double).to receive(:execute).with(query).and_return(nil)
        expect(user.find_user(id)).to be_nil
        expect(db_double).to have_received(:execute).with(query).once
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 7 }
      let(:query) { 'SELECT * FROM users WHERE id = 7' }

      it 'propagates the error' do
        allow(db_double).to receive(:execute).with(query).and_raise(StandardError, 'db down')
        expect { user.find_user(id) }.to raise_error(StandardError, 'db down')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Alice') }

    it 'returns the sum of internal variables (6)' do
      expect(user.bad_method).to eq(6)
    end
  end
end
