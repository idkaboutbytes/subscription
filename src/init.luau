--[=[
	Subscriptions are used in the callback for an [Observable](/api/Observable). Standard usage
	is as follows.

	```lua
	-- Constucts an observable which will emit a, b, c via a subscription
	Observable.new(function(sub)
		sub:Fire("a")
		sub:Fire("b")
		sub:Fire("c")
		sub:Complete() -- ends stream
	end)
	```
	@class Subscription
]=]


const MaidTaskUtils = require('./roblox_packages/MaidTaskUtils')

const ENABLE_STACK_TRACING = false

const Subscription = {}
Subscription.ClassName = 'Subscription'
Subscription.__index = Subscription

export type SubscriptionState = 'pending' | 'failed' | 'complete' | 'cancelled'

export type FireCallback<T...> = (T...) -> ()
export type CompleteCallback = () -> ()
export type FailCallback = (...any) -> ()

export type Subscription<T...> = {
	_state: SubscriptionState,
	_cleanupTask: MaidTaskUtils.MaidTask?,
	_fireCallback: FireCallback<T...>?,
	_failCallback: FailCallback?,
	_completeCallback: CompleteCallback?,
	_fireCountAfterDeath: number?,
	_source: string?,
	_observableSource: string?,
	Fire: (self: Subscription<T...>, T...) -> (),
	Fail: (self: Subscription<T...>, ...any) -> (),
	GetFireFailComplete: (self: Subscription<T...>) -> (FireCallback<T...>, FailCallback, CompleteCallback),
	GetFailComplete: (self: Subscription<T...>) -> (FailCallback, CompleteCallback),
	Complete: (self: Subscription<T...>, ...any) -> (),
	IsPending: (self: Subscription<T...>) -> boolean,
	Destroy: (self: Subscription<T...>) -> (),
	Disconnect: (self: Subscription<T...>) -> (),
	_assignCleanup: (self: Subscription<T...>, cleanupTask: MaidTaskUtils.MaidTask?) -> (),
	_doCleanup: (self: Subscription<T...>) -> (),
}

export type SubscriptionStateTypes = {
	PENDING: 'pending',
	FAILED: 'failed',
	COMPLETE: 'complete',
	CANCELLED: 'cancelled',
}

const SubscriptionStateTypes: SubscriptionStateTypes = table.freeze({
	PENDING = 'pending',
	FAILED = 'failed',
	COMPLETE = 'complete',
	CANCELLED = 'cancelled',
} :: SubscriptionStateTypes)

@checked
function Subscription.new<T...>(
	fireCallback: FireCallback<T...>?,
	failCallback: FailCallback?,
	completeCallback: CompleteCallback?,
	observableSource: string?
): Subscription<T...>
	assert(type(fireCallback) == 'function' or fireCallback == nil, 'Bad fireCallback')
	assert(type(failCallback) == 'function' or failCallback == nil, 'Bad failCallback')
	assert(type(completeCallback) == 'function' or completeCallback == nil, 'Bad completeCallback')

	return setmetatable({
		_state = SubscriptionStateTypes.PENDING,
		_source = if ENABLE_STACK_TRACING then debug.traceback('Subscription.new()', 3) else nil,
		_observableSource = observableSource,
		_fireCallback = fireCallback,
		_failCallback = failCallback,
		_completeCallback = completeCallback,
	}, Subscription) :: any
end

@checked
function Subscription.Fire<T...>(self: Subscription<T...>, ...: T...)
	if self._state == SubscriptionStateTypes.PENDING then
		if self._fireCallback then
			self._fireCallback(...)
		end
	elseif self._state == SubscriptionStateTypes.CANCELLED then
		if self._fireCountAfterDeath then
			self._fireCountAfterDeath += 1
		else
			self._fireCountAfterDeath = 1
		end

		if self._fireCountAfterDeath > 1 then
			warn(
				debug.traceback(
					string.format(
						'Subscription:Fire(%s) called %d times after death. Be sure to disconnect all events.',
						(tostring :: any)(...),
						self._fireCountAfterDeath or -1
					),
					2
				)
			)

			if ENABLE_STACK_TRACING then
				print(self._observableSource)
				print(self._source)
			end
		end
	end
end

@checked
function Subscription.Fail<T...>(self: Subscription<T...>, ...: any)
	if self._state ~= SubscriptionStateTypes.PENDING then
		return
	end

	self._state = SubscriptionStateTypes.FAILED

	if self._failCallback then
		self._failCallback(...)
	end

	self:_doCleanup()
end

@checked
function Subscription.GetFireFailComplete<T...>(
	self: Subscription<T...>
): (FireCallback<T...>, FailCallback, CompleteCallback)
	return function(...: T...)
		self:Fire(...)
	end, function(...)
		self:Fail(...)
	end, function(...)
		self:Complete(...)
	end
end

@checked
function Subscription.GetFailComplete<T...>(self: Subscription<T...>): (FailCallback, CompleteCallback)
	return function(...)
		self:Fail(...)
	end, function(...)
		self:Complete(...)
	end
end

@checked
function Subscription.Complete<T...>(self: Subscription<T...>, ...)
	if self._state ~= SubscriptionStateTypes.PENDING then
		return
	end

	self._state = SubscriptionStateTypes.COMPLETE

	if self._completeCallback then
		self._completeCallback(...)
	end

	self:_doCleanup()
end

@checked
function Subscription.IsPending<T...>(self: Subscription<T...>): boolean
	return self._state == SubscriptionStateTypes.PENDING
end

@checked
function Subscription._assignCleanup<T...>(self: Subscription<T...>, cleanupTask: MaidTaskUtils.MaidTask?)
	assert(self._cleanupTask == nil, 'Already have _cleanupTask')

	if MaidTaskUtils.isValidTask(cleanupTask) then
		if self._state ~= SubscriptionStateTypes.PENDING then
			MaidTaskUtils.doTask(cleanupTask)
			return
		end

		self._cleanupTask = cleanupTask
	elseif cleanupTask ~= nil then
		error('Bad cleanup cleanupTask')
	end
end

@checked
function Subscription._doCleanup<T...>(self: Subscription<T...>)
	const cleanupTask = self._cleanupTask

	if cleanupTask then
		self._cleanupTask = nil

		if MaidTaskUtils.isValidTask(cleanupTask) then
			MaidTaskUtils.doTask(cleanupTask)
		end
	end

	self._fireCallback = nil
	self._failCallback = nil
	self._completeCallback = nil
end

@checked
function Subscription.Destroy<T...>(self: Subscription<T...>)
	if self._state == SubscriptionStateTypes.PENDING then
		self._state = SubscriptionStateTypes.CANCELLED
	end

	self:_doCleanup()
end

Subscription.Disconnect = Subscription.Destroy

return Subscription
