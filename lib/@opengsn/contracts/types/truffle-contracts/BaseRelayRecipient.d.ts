/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import BN from "bn.js";
import { EventData, PastEventOptions } from "web3-eth-contract";

export interface BaseRelayRecipientContract
  extends Truffle.Contract<BaseRelayRecipientInstance> {
  "new"(meta?: Truffle.TransactionDetails): Promise<BaseRelayRecipientInstance>;
}

type AllEvents = never;

export interface BaseRelayRecipientInstance extends Truffle.ContractInstance {
  versionRecipient(txDetails?: Truffle.TransactionDetails): Promise<string>;

  trustedForwarder(txDetails?: Truffle.TransactionDetails): Promise<string>;

  /**
   * return if the forwarder is trusted to forward relayed transactions to us. the forwarder is required to verify the sender's signature, and verify the call is not a replay.
   */
  isTrustedForwarder(
    forwarder: string,
    txDetails?: Truffle.TransactionDetails
  ): Promise<boolean>;

  methods: {
    versionRecipient(txDetails?: Truffle.TransactionDetails): Promise<string>;

    trustedForwarder(txDetails?: Truffle.TransactionDetails): Promise<string>;

    /**
     * return if the forwarder is trusted to forward relayed transactions to us. the forwarder is required to verify the sender's signature, and verify the call is not a replay.
     */
    isTrustedForwarder(
      forwarder: string,
      txDetails?: Truffle.TransactionDetails
    ): Promise<boolean>;
  };

  getPastEvents(event: string): Promise<EventData[]>;
  getPastEvents(
    event: string,
    options: PastEventOptions,
    callback: (error: Error, event: EventData) => void
  ): Promise<EventData[]>;
  getPastEvents(event: string, options: PastEventOptions): Promise<EventData[]>;
  getPastEvents(
    event: string,
    callback: (error: Error, event: EventData) => void
  ): Promise<EventData[]>;
}
