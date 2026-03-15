import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: Plan = .yearly
    
    enum Plan: String, CaseIterable {
        case monthly, yearly
        var price: String { self == .monthly ? "$7.99/month" : "$49.99/year" }
        var savings: String? { self == .yearly ? "Save 48%" : nil }
        var period: String { self == .monthly ? "Monthly" : "Yearly" }
    }
    
    private let features = [
        ("infinity", "Unlimited analyses"),
        ("brain.head.profile", "AI coaching with specific drills"),
        ("chart.line.uptrend.xyaxis", "Progress tracking over time"),
        ("arrow.left.and.right", "Side-by-side session comparison"),
        ("square.and.arrow.up", "Share branded analysis cards"),
        ("bolt.fill", "Priority processing"),
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("✨").font(.system(size: 48))
                    Text("Upgrade to Pro").font(.title).fontWeight(.bold)
                    Text("Unlock your full potential").font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                // Features
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(features, id: \.0) { icon, text in
                        HStack(spacing: 12) {
                            Image(systemName: icon)
                                .foregroundColor(DesignSystem.Colors.gold)
                                .frame(width: 24)
                            Text(text).font(.subheadline)
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
                
                // Plan selection
                HStack(spacing: 12) {
                    ForEach(Plan.allCases, id: \.self) { plan in
                        Button(action: { selectedPlan = plan }) {
                            VStack(spacing: 4) {
                                if let savings = plan.savings {
                                    Text(savings)
                                        .font(.caption2).fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 2)
                                        .background(Capsule().fill(DesignSystem.Colors.gold))
                                }
                                Text(plan.period).font(.subheadline).fontWeight(.semibold)
                                Text(plan.price).font(.caption).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(selectedPlan == plan ? DesignSystem.Colors.cricketGreen.opacity(0.2) : Color(UIColor.secondarySystemBackground)))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedPlan == plan ? DesignSystem.Colors.cricketGreenLight : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Subscribe button
                Button(action: subscribe) {
                    Text("Subscribe Now")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignSystem.Colors.cricketGreenLight)
                        .foregroundColor(.white)
                        .cornerRadius(DesignSystem.Layout.cornerRadius)
                }
                
                // Fine print
                VStack(spacing: 4) {
                    Text("Cancel anytime. Auto-renews.").font(.caption2).foregroundColor(.secondary)
                    HStack(spacing: 16) {
                        Button("Restore Purchases") { restorePurchases() }
                            .font(.caption2).foregroundColor(.secondary)
                        Button("Terms") {}
                            .font(.caption2).foregroundColor(.secondary)
                        Button("Privacy") {}
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Pro")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func subscribe() {
        // TODO: Integrate RevenueCat/StoreKit 2
        print("Subscribe to \(selectedPlan.rawValue)")
    }
    
    private func restorePurchases() {
        // TODO: Integrate RevenueCat/StoreKit 2
        print("Restore purchases")
    }
}
