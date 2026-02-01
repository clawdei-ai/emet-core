import { http, createConfig, createStorage } from 'wagmi';
import { base } from 'wagmi/chains';
import { coinbaseWallet, injected, walletConnect } from 'wagmi/connectors';

const projectId = 'cee26362e9b157808528772a8c933d9d';

export const config = createConfig({
  chains: [base],
  connectors: [
    injected(),
    coinbaseWallet({
      appName: 'EMET Protocol',
      preference: 'all',
    }),
    walletConnect({
      projectId,
      showQrModal: true,
      metadata: {
        name: 'EMET Protocol',
        description: 'Trustless truth verification on Base',
        url: 'https://app.emet-protocol.com',
        icons: ['https://app.emet-protocol.com/favicon.ico'],
      },
    }),
  ],
  storage: createStorage({
    storage: typeof window !== 'undefined' ? window.localStorage : undefined,
    key: 'emet',
  }),
  transports: {
    [base.id]: http(),
  },
});
