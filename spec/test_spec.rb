require 'spec_helper'

RSpec.describe User do
  describe '#initialize' do
    context 'with valid name' do
      let(:name) { 'Alice' }
      let(:user) { described_class.new(name) }

      it 'sets @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'without arguments' do
      it 'raises ArgumentError' do
        expect do
          described_class.new
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#find_user' do
    let(:name) { 'Bob' }
    let(:user) { described_class.new(name) }
    let(:db_double) { double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'with integer id' do
      let(:id) { 42 }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }
      let(:result) { [{ 'id' => 42, 'name' => 'Bob' }] }

      it 'builds correct query and returns DB results' do
        expect(db_double).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with string id containing characters' do
      let(:id) { '1 OR 1=1' }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }
      let(:result) { 'anything' }

      it 'passes unsanitized id through to DB' do
        expect(db_double).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with nil id' do
      let(:id) { nil }
      let(:query) { 'SELECT * FROM users WHERE id = ' }
      let(:result) { [] }

      it 'converts nil to empty string in query and returns DB results' do
        expect(db_double).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when DB returns nil' do
      let(:id) { 7 }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'returns nil' do
        expect(db_double).to receive(:execute).with(query).and_return(nil)
        expect(user.find_user(id)).to be_nil
      end
    end

    context 'when DB raises an error' do
      let(:id) { 1 }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'propagates the error' do
        expect(db_double).to receive(:execute).with(query).and_raise(StandardError, 'db error')
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'db error')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Test') }

    it 'returns the sum of constants 1, 2, and 3' do
      expect(user.bad_method).to eq(6)
    end
  end
end
