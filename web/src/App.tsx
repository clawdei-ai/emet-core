import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { WagmiProvider } from 'wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

import { config } from './lib/wagmi';
import { Layout } from './components/Layout';
import { Home } from './pages/Home';
import { SubmitClaim } from './pages/SubmitClaim';
import { ClaimsList } from './pages/ClaimsList';
import { ClaimDetail } from './pages/ClaimDetail';
import { MyActivity } from './pages/MyActivity';
import { Concentration } from './pages/Concentration';
import { KyaStack } from './pages/KyaStack';

const queryClient = new QueryClient();

export default function App() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          <Routes>
            <Route element={<Layout />}>
              <Route path="/" element={<Home />} />
              <Route path="/submit" element={<SubmitClaim />} />
              <Route path="/claims" element={<ClaimsList />} />
              <Route path="/claims/:id" element={<ClaimDetail />} />
              <Route path="/activity" element={<MyActivity />} />
              <Route path="/concentration" element={<Concentration />} />
              <Route path="/kya" element={<KyaStack />} />
            </Route>
          </Routes>
        </BrowserRouter>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
