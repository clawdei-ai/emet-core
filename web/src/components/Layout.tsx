import { Link, Outlet, useLocation } from 'react-router-dom';
import { WalletButton } from './WalletButton';

const NAV_ITEMS = [
  { path: '/', label: 'Home' },
  { path: '/submit', label: 'Submit Claim' },
  { path: '/claims', label: 'Claims' },
  { path: '/concentration', label: 'Concentration' },
  { path: '/activity', label: 'My Activity' },
];

export function Layout() {
  const location = useLocation();

  return (
    <div className="app">
      <header className="header">
        <div className="header-inner">
          <Link to="/" className="logo">
            <span className="logo-icon">◆</span> EMET
          </Link>
          <nav className="nav">
            {NAV_ITEMS.map((item) => (
              <Link
                key={item.path}
                to={item.path}
                className={`nav-link ${location.pathname === item.path ? 'active' : ''}`}
              >
                {item.label}
              </Link>
            ))}
          </nav>
          <WalletButton />
        </div>
      </header>
      <main className="main">
        <Outlet />
      </main>
      <footer className="footer">
        <p>
          EMET Protocol on{' '}
          <a href="https://basescan.org/address/0x69FC0F525F15DFB57e762cD2c570114433AFc6e2" target="_blank" rel="noreferrer">
            Base
          </a>{' '}
          · Trustless truth verification
        </p>
      </footer>
    </div>
  );
}
