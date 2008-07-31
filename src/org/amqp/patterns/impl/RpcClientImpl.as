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
package org.amqp.patterns.impl
{
	import de.polygonal.ds.ArrayedQueue;
	
	import flash.events.EventDispatcher;
	import flash.utils.ByteArray;
	
	import org.amqp.BasicConsumer;
	import org.amqp.Connection;
	import org.amqp.ProtocolEvent;
	import org.amqp.headers.BasicProperties;
	import org.amqp.methods.basic.Consume;
	import org.amqp.methods.basic.Deliver;
	import org.amqp.patterns.CorrelatedMessageEvent;
	import org.amqp.patterns.RpcClient;
	import org.amqp.util.Guid;
	import org.amqp.util.Properties;

	public class RpcClientImpl extends AbstractDelegate implements RpcClient, BasicConsumer
	{
		public var routingKey:String;
		
		public var replyQueue:String;
		public var consumerTag:String;
		
		private var sendBuffer:ArrayedQueue = new ArrayedQueue(100);
		
		private var dispatcher:EventDispatcher = new EventDispatcher();
		
		public function RpcClientImpl(c:Connection) {
			super(c);	
		}

		public function send(o:*,callback:Function):void {
			if (null != o) {
				if (null == consumerTag) {
					buffer(o,callback);
				}
				else {
					dispatch(o,callback);
				}
			}
		}	
		
		private function buffer(o:*,callback:Function):void {
			var o:Object = {payload:o,handler:callback}; 
			sendBuffer.enqueue(o);
		}
		
		private function drainBuffer():void {
			while(!sendBuffer.isEmpty()) {
				const o:Object = sendBuffer.dequeue();
				var data:* = o.payload;
				var callback:Function = o.handler;
				dispatch(data,callback);
			}
		}
		
		private function dispatch(o:*,callback:Function):void {
			var correlationId:String = Guid.next();
			var data:ByteArray = new ByteArray();
			serializer.serialize(o,data);
        	var props:BasicProperties = Properties.getBasicProperties();
			props.correlationid = correlationId;
			props.replyto = replyQueue;
			publish(exchange,routingKey,data,props);
			dispatcher.addEventListener(correlationId,callback);
		}
		
		override protected function onRequestOk(event:ProtocolEvent):void {			
			declareExchange(exchange,exchangeType);
			setupReplyQueue();	
		}
		
		override protected function onQueueDeclareOk(event:ProtocolEvent):void {
			replyQueue = getReplyQueue(event);
			var consume:Consume = new Consume();
        	consume.queue = replyQueue;
        	consume.noack = true;
        	sessionHandler.register(consume, this);
		}
		
		public function onConsumeOk(tag:String):void {
        	consumerTag = tag;
        	drainBuffer();
        }
        
		public function onCancelOk(tag:String):void {}
		
		public function onDeliver(method:Deliver, 
								  properties:BasicProperties,
								  body:ByteArray):void {
			var result:* = serializer.deserialize(body);											  									  	
			dispatcher.dispatchEvent(new CorrelatedMessageEvent(properties.correlationid,result));
		}
		
	}
}