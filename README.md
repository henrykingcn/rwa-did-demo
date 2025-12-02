# RWA Compliance & Identity Verification System

> **🔥 LIVE DEMO AVAILABLE NOW: [rwa.henryhl.wang](http://rwa.henryhl.wang) 🔥**
>
> **Presentation Sildes at: [rwa.henryhl.wang/ppt](http://rwa.henryhl.wang/ppt)**
>
> Don't just read the code—**experience the future** of Real-World Asset compliance! We have deployed the full interactive system online. Visit our official site to witness the next generation of decentralized identity verification in action. 🚀

This repository contains the implementation of a decentralized architecture designed to solve compliance and identity verification issues for Real-World Assets (RWA) on the blockchain. It includes the core Solidity smart contracts and a web-based presentation/demonstration interface.

## 📂 Repository Structure

| File | Description |
| :--- | :--- |
| **`system.sol`** | The core smart contract containing Identity, Compliance, and RWA logic. |
| **`index.html`** | Main entry point for the web interface. |
| **`logic.html`** | Visualization of the system architecture and logic flow. |
| **`ppt.html`** | Web-based presentation slide deck explaining the project. |
| **`styles.css`** | Styling for the HTML pages. |

---

## 🌐 🚀 Live Demo & Frontend

**✨ The best way to experience this project is via our live deployment! ✨**

👉 **[Visit rwa.henryhl.wang](http://rwa.henryhl.wang)**

Our live site offers a seamless, interactive demonstration of the system architecture and logic flow. No installation required—just click and explore!

### Running Locally (Optional)
If you prefer to run the frontend locally:
1.  Clone or download this repository to your local machine.
2.  Navigate to the folder.
3.  Double-click `index.html` or `ppt.html` to open them in your browser.
4.  **Note**: For the best experience, use a local server (like Live Server in VS Code) to avoid CORS issues if the HTML fetches local assets.

---

## 🚀 Getting Started with Smart Contracts

To compile and deploy the smart contracts manually, we recommend using **Remix IDE** (an online development environment for Ethereum). This requires no local installation.

### Prerequisites
* A modern web browser (Chrome, Firefox, Brave).
* [MetaMask](https://metamask.io/) extension installed (optional, for testnet deployment).

---

## 🛠️ Compilation & Deployment (via Remix IDE)

### Step 1: Load the Contract
1.  Open [Remix IDE](https://remix.ethereum.org/).
2.  In the "File Explorers" tab, create a new file named `system.sol`.
3.  Copy the content of `system.sol` from this repository and paste it into Remix.

### Step 2: Compile
1.  Go to the **"Solidity Compiler"** tab (3rd icon on the left).
2.  Select a generic compiler version (e.g., `0.8.x` matching the pragma in the code).
3.  Click the blue **"Compile system.sol"** button.
4.  Ensure there are no red errors (yellow warnings are usually acceptable).

### Step 3: Deploy
1.  Go to the **"Deploy & Run Transactions"** tab (4th icon on the left).
2.  **Environment**: 
    * Select **"Remix VM (Cancun)"** for local, instant testing (Recommended).
    * Select **"Injected Provider - MetaMask"** if you want to deploy to a live testnet (e.g., Sepolia).
3.  **Contract**: Ensure `System` (or the main contract name) is selected in the dropdown.
4.  Click **"Deploy"**.
5.  Check the console at the bottom for the green checkmark confirming deployment.

---

## 🧪 How to Run Basic Tests

Once deployed, you can interact with the contract functions under the "Deployed Contracts" section in Remix.

### Test Case 1: Organization Setup (Governance)
*Goal: Create a new Issuer Organization.*

1.  Expand the deployed contract instance.
2.  Locate the `addIssuer` or governance proposal function (depending on your governance logic).
3.  Input the required parameters:
    * `_name`: "Test Bank"
    * `_scope`: "US"
    * `_stake`: `10000`
4.  Click **transact**.
5.  **Verify**: Call the `issuers` mapping with the new address to confirm `isActive` is `true`.

### Test Case 2: Identity Issuance
*Goal: Issue a valid DID to a user.*

1.  Switch to a different account in the "Account" dropdown (acting as the User). Copy this address.
2.  Switch back to the Admin/Issuer account.
3.  Locate the `issueIdentity` function.
4.  Input:
    * `_user`: [User Address copied above]
    * `_region`: "US"
    * `_role`: "Investor"
5.  Click **transact**.

### Test Case 3: Compliance Check
*Goal: Verify the Compliance Engine logic.*

1.  Locate the `checkCompliance` function (blue button, read-only).
2.  Input:
    * `_user`: [User Address]
    * `_reqRegion`: "US"
    * `_reqIssuer`: [Issuer Address]
3.  Click **call**.
4.  **Expected Result**: It should return `true`.
5.  **Negative Test**: Change `_reqRegion` to "EU" and click call. It should return `false`.

## 📄 License

[Choose a license, e.g., MIT]
