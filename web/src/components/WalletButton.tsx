import { useAccount, useConnect, useDisconnect, useReadContract } from 'wagmi';
import { CONTRACTS } from '../contracts/addresses';
import { EMETTokenABI } from '../contracts/abis';
import { formatEMET } from '../lib/format';

export function WalletButton() {
  const { address, isConnected } = useAccount();
  const { connectors, connect } = useConnect();
  const { disconnect } = useDisconnect();

  const { data: balance } = useReadContract({
    address: CONTRACTS.EMETToken as `0x${string}`,
    abi: EMETTokenABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  if (isConnected && address) {
    return (
      <div className="wallet-connected">
        {balance !== undefined && (
          <span className="wallet-balance">{formatEMET(balance as bigint)} EMET</span>
        )}
        <span className="wallet-address">
          {address.slice(0, 6)}...{address.slice(-4)}
        </span>
        <button className="btn btn-small btn-disconnect" onClick={() => disconnect()}>
          ✕
        </button>
      </div>
    );
  }

  // Filter to unique named connectors, prefer known ones
  const seen = new Set<string>();
  const uniqueConnectors = connectors.filter((c) => {
    const name = c.name === 'Injected' ? 'Browser Wallet' : c.name;
    if (seen.has(name)) return false;
    seen.add(name);
    return true;
  });

  return (
    <div className="wallet-options">
      {uniqueConnectors.map((connector) => (
        <button
          key={connector.uid}
          className="btn btn-connect"
          onClick={() => connect({ connector })}
        >
          {connector.name === 'Injected' ? 'Browser Wallet' : connector.name}
        </button>
      ))}
    </div>
  );
}
