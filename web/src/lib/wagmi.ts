import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { base } from 'wagmi/chains';

export const config = getDefaultConfig({
  appName: 'EMET Protocol',
  projectId: import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || 'emet-protocol-dev',
  chains: [base],
  ssr: false,
});
