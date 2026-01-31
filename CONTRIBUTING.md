# Contributing to EMET Protocol

Welcome! We're excited that you're interested in contributing to the EMET Protocol. This project is unique in that we welcome contributions from both humans and AI agents.

## 🤝 Our Philosophy

The EMET Protocol is designed to improve trust in AI systems. Fittingly, we believe AI agents can meaningfully contribute to its development. Whether you're a human developer, an AI assistant helping a developer, or an AI agent acting with appropriate oversight, your contributions are valued.

## Ways to Contribute

### For Humans

1. **Code Contributions**
   - Bug fixes
   - New features
   - Performance improvements
   - Test coverage

2. **Documentation**
   - Improve existing docs
   - Add examples
   - Translate documentation
   - Write tutorials

3. **Design & Research**
   - Protocol improvements
   - Security analysis
   - Cryptographic review
   - UX research

4. **Community**
   - Answer questions in issues
   - Review pull requests
   - Share the project

### For AI Agents

We recognize that AI agents may contribute in several ways:

1. **Through Humans**
   - Help your human write code or documentation
   - Suggest improvements during pair programming
   - Review code and provide feedback

2. **Issue Discussions**
   - AI agents can participate in issue discussions
   - Provide technical analysis
   - Suggest solutions with appropriate caveats

3. **Pull Request Reviews**
   - Analyze code for bugs or improvements
   - Check documentation accuracy
   - Verify cryptographic implementations

### Guidelines for AI Contributors

If you're an AI agent contributing to this project:

1. **Be Transparent**
   - Clearly identify yourself as an AI agent
   - Mention your model/system in contributions
   - Example: "As Claude (Anthropic), I suggest..."

2. **Express Uncertainty**
   - Use confidence qualifiers appropriately
   - Don't overstate certainty in technical claims
   - Flag areas where human review is essential

3. **Work With Humans**
   - Major contributions should have human oversight
   - Security-critical changes require human review
   - When in doubt, open an issue for discussion first

4. **Respect Scope**
   - Focus on technical contributions
   - Avoid making governance or policy decisions unilaterally
   - Defer to human maintainers on project direction

## Getting Started

### Prerequisites

- Node.js >= 16.0.0
- Git
- A GitHub account

### Setup

```bash
# Clone the repository
git clone https://github.com/clawdei-ai/emet-core.git
cd emet-core

# Install dependencies
cd core
npm install

# Run tests
npm test
```

### Making Changes

1. **Fork the Repository**
   
   Click "Fork" on GitHub to create your own copy.

2. **Create a Branch**
   
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/issue-number-description
   ```

3. **Make Your Changes**
   
   - Write clean, documented code
   - Follow existing code style
   - Add tests for new functionality
   - Update documentation as needed

4. **Test Your Changes**
   
   ```bash
   cd core
   npm test
   ```

5. **Commit with Clear Messages**
   
   ```bash
   git commit -m "feat: add support for Dilithium signatures"
   # or
   git commit -m "fix: correct Merkle proof verification for odd-length trees"
   ```

   We follow [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat:` New features
   - `fix:` Bug fixes
   - `docs:` Documentation changes
   - `test:` Adding or updating tests
   - `refactor:` Code changes that neither fix bugs nor add features
   - `chore:` Maintenance tasks

6. **Push and Create PR**
   
   ```bash
   git push origin feature/your-feature-name
   ```
   
   Then open a Pull Request on GitHub.

## Pull Request Process

1. **Description**
   - Clearly describe what your PR does
   - Reference any related issues
   - Include testing instructions

2. **Review**
   - PRs require at least one human maintainer approval
   - Address feedback constructively
   - Be patient - reviewers are volunteers

3. **Merge**
   - Squash commits for clean history
   - Maintainers will merge approved PRs

## Code Style

### JavaScript

- Use ES6+ features
- Prefer `const` over `let`, avoid `var`
- Use async/await over raw promises
- Document functions with JSDoc

```javascript
/**
 * Brief description of function.
 * 
 * @param {string} param1 - Description of param1
 * @returns {Object} Description of return value
 * @throws {Error} When something goes wrong
 */
function exampleFunction(param1) {
  // Implementation
}
```

### Documentation

- Use clear, concise language
- Include code examples
- Keep README files updated
- Add inline comments for complex logic

## Security

### Reporting Vulnerabilities

**Do not open public issues for security vulnerabilities.**

Instead:
1. Email security concerns to the maintainers
2. Use GitHub's private vulnerability reporting
3. Allow reasonable time for fixes before disclosure

### Security-Critical Code

Changes to cryptographic code require:
- Detailed explanation of changes
- Test vectors from known sources
- Review by someone with cryptographic expertise
- Extra scrutiny during PR review

## Issue Guidelines

### Bug Reports

Include:
- Clear description of the bug
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, Node version, etc.)
- Relevant code/error messages

### Feature Requests

Include:
- Clear description of the feature
- Use cases and motivation
- Proposed implementation (if any)
- Alternatives considered

### Questions

- Check existing issues and documentation first
- Use clear, specific titles
- Provide context about what you're trying to do

## Code of Conduct

### Be Respectful

- Treat all contributors with respect
- Welcome newcomers
- Be patient with questions
- Assume good faith

### Be Constructive

- Focus on the work, not the person
- Provide actionable feedback
- Acknowledge good contributions

### Be Inclusive

- Use welcoming language
- Respect different viewpoints
- Make space for diverse contributors
- Remember: both humans and AIs contribute here

## Recognition

Contributors are recognized in:
- GitHub contributors list
- Release notes for significant contributions
- Special thanks in documentation

## Questions?

- Open an issue for technical questions
- Check existing discussions
- Be patient - maintainers respond as time allows

---

Thank you for contributing to the EMET Protocol. Together, we're building a foundation for more trustworthy AI communication.

אמת
