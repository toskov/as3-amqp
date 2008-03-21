/**
 * ---------------------------------------------------------------------------
 *   Copyright (C) 2008 0x6e6562
 *
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *   You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 * ---------------------------------------------------------------------------
 **/
package org.amqp.impl
{
	//import de.polygonal.ds.Iterator;
	//import de.polygonal.ds.PriorityQueue;
	
	import mx.managers.layoutClasses.PriorityQueue;
	
	import org.amqp.BaseCommandReceiver;
	import org.amqp.Command;
	import org.amqp.Method;
	import org.amqp.ProtocolEvent;
	import org.amqp.error.IllegalStateError;
	import org.amqp.headers.AccessProperties;
	import org.amqp.headers.ChannelProperties;
	import org.amqp.headers.ConnectionProperties;
	import org.amqp.methods.access.RequestOk;
	import org.amqp.methods.channel.CloseOk;
	import org.amqp.methods.channel.OpenOk;

	public class SessionStateHandler extends BaseCommandReceiver
	{		
		private static const STATE_CLOSED:int = 0;		
		private static const STATE_CONNECTION:int = new ConnectionProperties().getClassId();
		private static const STATE_CHANNEL:int = new ChannelProperties().getClassId();
		private static const STATE_ACCESS:int = new AccessProperties().getClassId();
		private static const STATE_OPEN:int = new AccessProperties().getClassId() + 1;
		
		protected var ticket:int;		
		protected var state:int = STATE_CONNECTION;
		protected var queue:PriorityQueue = new PriorityQueue();
		
		public function SessionStateHandler(){
			addEventListener(new OpenOk(), onOpenOk);
			addEventListener(new RequestOk(), onRequestOk);
			addEventListener(new CloseOk(), onCloseOk);
		}
		
		override public function forceClose():void{
			trace("forceClose called");
			transition(STATE_CLOSED);
		}
		
		override public function closeGracefully():void{
			trace("closeGracefully called");
			transition(STATE_CLOSED);
		}
		
		public function dispatch(cmd:Command):void {			
			switch(state) {
				case STATE_CLOSED: { stateError(cmd.method.getClassId()); }
				case STATE_CONNECTION: {
					if (cmd.method.getClassId() > STATE_CHANNEL) {
						enqueueCommand(cmd);
					}
					else {
						sendCommand(cmd);
					}
					break;
				}
				case STATE_CHANNEL: {
					if (cmd.method.getClassId() > STATE_ACCESS) {
						enqueueCommand(cmd);
					}
					else {
						sendCommand(cmd);
					}
					break;
				}
				default: {
					flushQueue();
					sendCommand(cmd);
				}
			}										
		}
		
		public function onOpenOk(event:ProtocolEvent):void {
			transition(STATE_CHANNEL);
			flushQueue(STATE_ACCESS);			
			//dispatchAfterOpenEvent();			
		}
		
		public function onRequestOk(event:ProtocolEvent):void {
			transition(STATE_ACCESS);
			var accessRequestOk:RequestOk = event.command.method as RequestOk;
			ticket = accessRequestOk._ticket;
			flushQueue();			
		}
		
		/**
		 *  This frees up any resources associated with this session.
		 **/
		public function onCloseOk(event:ProtocolEvent):void {
			ticket = -1;
			transition(STATE_CONNECTION);
			//dispatchAfterCloseEvent();
		}
		
		/**
		 * Enqueues a command in order of ascending class id.
		 **/
		private function enqueueCommand(cmd:Command):void {
			queue.addObject(cmd, cmd.method.getClassId());
		}
		
		private function flushQueue(limit:int = -1):void {
			
			var cmd:Command = queue.removeSmallest() as Command;
			if (null == cmd) return;
			var classId:int = cmd.method.getClassId();	
			
			if (limit > -1) {
				if (classId > limit) {
					queue.addObject(cmd, classId);
				}
				else {
					sendCommand(cmd);
					flushQueue(limit);
				}
			}
			else {
				sendCommand(cmd);
				flushQueue();
			}										
		}
		
		private function sendCommand(cmd:Command):void {
			var method:Method = cmd.method;
			if (method.getClassId() > STATE_ACCESS) {
				method._ticket = ticket;
				trace("--------> " + method.getMethodId());
				trace("--------> " + method._ticket);
				session.sendCommand(cmd);
			}
			else {
				session.sendCommand(cmd);
			}	
		}
		
		/**
		 * Cheap hack of an FSM
		 **/
		private function transition(newState:int):void {
			switch (state) {				
				case STATE_CLOSED: { stateError(newState); }				
				case STATE_CONNECTION: {
					if (newState == STATE_ACCESS) {
						stateError(newState);
					}
					else {
						state = newState;
					}
					break;
				}
				case STATE_ACCESS: {
					if (newState == STATE_CHANNEL) {
						stateError(newState);
					}
					else {
						state = newState;
					}
					break;
				}
				default: state = newState;
			}
		}
		
		/**
		 * Renders an error according to the attempted transition.
		 **/
		private function stateError(newState:int):void {
			throw new IllegalStateError("Illegal state transition: " + state + " ---> " + newState)	
		}
	}
}